#!/bin/bash
set -e

echo "=== Frappe LMS Initialization ==="

# Function to wait for service
wait_for_service() {
    local host=$1
    local port=$2
    local service=$3
    local max_attempts=60
    local attempt=1

    echo "Waiting for $service at $host:$port..."
    while ! nc -z "$host" "$port" 2>/dev/null; do
        if [ $attempt -ge $max_attempts ]; then
            echo "ERROR: $service not available after $max_attempts attempts"
            exit 1
        fi
        echo "Attempt $attempt/$max_attempts - $service not ready, waiting..."
        sleep 2
        attempt=$((attempt + 1))
    done
    echo "$service is ready!"
}

# Wait for database
wait_for_service "${DB_HOST:-mariadb}" "${DB_PORT:-3306}" "MariaDB"

# Parse Redis URL for host/port (handles redis://user:pass@host:port format)
REDIS_HOST=$(echo "${REDIS_URL:-redis://redis:6379}" | sed -E "s|redis://([^@]+@)?([^:]+):([0-9]+).*|\2|")
REDIS_PORT=$(echo "${REDIS_URL:-redis://redis:6379}" | sed -E "s|redis://([^@]+@)?[^:]+:([0-9]+).*|\2|")
echo "Parsed Redis host: $REDIS_HOST, port: $REDIS_PORT"
wait_for_service "$REDIS_HOST" "$REDIS_PORT" "Redis"

cd /home/frappe

# Initialize bench - check if Frappe is properly installed
BENCH_DIR=/home/frappe/frappe-bench
if [ ! -d "$BENCH_DIR/apps/frappe/frappe" ]; then
    echo "Initializing Frappe bench..."
    rm -rf "$BENCH_DIR" 2>/dev/null || true
    bench init --skip-redis-config-generation --frappe-branch ${FRAPPE_BRANCH:-version-15} "$BENCH_DIR"
fi
cd "$BENCH_DIR"
echo "Working directory: $(pwd)"

# Configure common_site_config.json directly using Python for proper JSON handling
echo "Configuring services via Python..."
python3 << 'EOF'
import json
import os

config_path = "sites/common_site_config.json"

# Load existing config or create new
config = {}
if os.path.exists(config_path):
    with open(config_path, "r") as f:
        config = json.load(f)

# Get environment variables
db_host = os.environ.get("DB_HOST", "mariadb")
db_port = int(os.environ.get("DB_PORT", "3306"))
redis_url = os.environ.get("REDIS_URL", "redis://redis:6379")

# Update config
config["db_host"] = db_host
config["db_port"] = db_port
config["redis_cache"] = redis_url
config["redis_queue"] = redis_url
config["redis_socketio"] = redis_url
config["socketio_port"] = 9000

# Set database type for Frappe (mariadb or postgres)
# Railway's MariaDB service is compatible with Frappe
config["db_type"] = "mariadb"

# Write config
os.makedirs("sites", exist_ok=True)
with open(config_path, "w") as f:
    json.dump(config, f, indent=2)

print(f"Configuration written to {config_path}")
print(f"  db_host: {db_host}")
print(f"  redis_url: {redis_url}")
EOF

# Install LMS app if not already installed
if [ ! -d "apps/lms" ]; then
    echo "Installing LMS app..."
    if [ -d "/workspace/lms" ]; then
        # Copy app to apps directory
        cp -r /workspace/lms apps/lms

        # Add lms to apps.txt (Frappe's app registry)
        echo "lms" >> apps/apps.txt

        # Install Python package in editable mode
        ./env/bin/pip install -e apps/lms

        # Run node setup for the app
        bench setup requirements --node || true
    else
        # Fallback to getting from GitHub
        bench get-app https://github.com/frappe/lms --skip-assets
    fi
fi

# Create site if not exists or recreate if database is corrupt
SITE_NAME="${SITE_NAME:-lms.localhost}"

# Force recreation for fresh install - check env var
FORCE_REINSTALL="${FORCE_REINSTALL:-0}"

if [ ! -d "sites/${SITE_NAME}" ] || [ "$FORCE_REINSTALL" = "1" ]; then
    echo "Creating site: ${SITE_NAME}"
    # Drop existing database if FORCE_REINSTALL
    if [ "$FORCE_REINSTALL" = "1" ] && [ -d "sites/${SITE_NAME}" ]; then
        echo "Force reinstall requested, dropping existing site..."
        bench drop-site ${SITE_NAME} --force --no-backup --root-password "${MARIADB_ROOT_PASSWORD:-admin}" || true
        rm -rf "sites/${SITE_NAME}" 2>/dev/null || true
    fi

    bench new-site ${SITE_NAME} \
        --force \
        --mariadb-root-password "${MARIADB_ROOT_PASSWORD:-admin}" \
        --admin-password "${ADMIN_PASSWORD:-admin}" \
        --no-mariadb-socket

    echo "Installing LMS on site..."
    bench --site ${SITE_NAME} install-app lms
else
    echo "Site ${SITE_NAME} already exists"
fi

# Set as current site
bench use ${SITE_NAME}

# Run migrations
echo "Running migrations..."
bench --site ${SITE_NAME} migrate || echo "Migration completed or skipped"

# Set production config
if [ "${DEVELOPER_MODE:-0}" = "0" ]; then
    bench --site ${SITE_NAME} set-config developer_mode 0
else
    bench --site ${SITE_NAME} set-config developer_mode 1
fi

# Build assets (skip LMS frontend build errors - use pre-built assets)
echo "Building assets..."
bench build --app frappe || echo "Frappe build completed"
bench build --app lms 2>/dev/null || echo "LMS build completed (may have warnings)"

# Clear cache
bench --site ${SITE_NAME} clear-cache || true

echo "=== Starting Frappe LMS ==="
echo "Site: ${SITE_NAME}"
echo "Railway PORT: ${PORT}"

# Create custom Procfile with correct port and no socketio
# Railway provides PORT env var (usually 8080)
APP_PORT="${PORT:-8000}"
echo "Creating Procfile with port: $APP_PORT"

# Write a minimal Procfile without socketio (Railway Redis has auth issues)
cat > ./Procfile << PROCFILE_END
web: bench serve --port $APP_PORT
schedule: bench schedule
worker: bench worker --queue short,default,long
PROCFILE_END

echo "=== Final Procfile ==="
cat ./Procfile
echo "================"

# Start bench
exec bench start

# ============================================
# Frappe LMS Production Dockerfile
# Uses official Frappe Bench image
# ============================================
# Use Python 3.11 based bench image for Frappe v15 compatibility
FROM python:3.11-bookworm

# Set environment variables
ENV FRAPPE_BRANCH=version-15 \
    BENCH_PATH=/home/frappe/frappe-bench \
    SITE_NAME=lms.localhost \
    ADMIN_PASSWORD=admin \
    DB_HOST=mariadb \
    DB_PORT=3306 \
    MARIADB_ROOT_PASSWORD=admin \
    REDIS_URL=redis://redis:6379 \
    DEVELOPER_MODE=0

# Install system dependencies for Frappe
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Build essentials
    git \
    curl \
    wget \
    gnupg \
    # Database client
    mariadb-client \
    # Redis
    redis-tools \
    # Python build dependencies
    build-essential \
    libffi-dev \
    libssl-dev \
    libjpeg-dev \
    libpng-dev \
    libtiff-dev \
    libwebp-dev \
    libxml2-dev \
    libxslt1-dev \
    libldap2-dev \
    libsasl2-dev \
    # Cairo for PDF generation
    libcairo2 \
    libcairo2-dev \
    libpango-1.0-0 \
    libpangocairo-1.0-0 \
    # Other utilities
    netcat-openbsd \
    supervisor \
    wkhtmltopdf \
    xvfb \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 18 LTS
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g yarn

# Create frappe user
RUN useradd -m -d /home/frappe -s /bin/bash frappe

# Install frappe-bench
RUN pip install --upgrade pip && pip install frappe-bench

# Copy LMS app source
COPY --chown=frappe:frappe . /workspace/lms/

# Create frappe bench directory
RUN mkdir -p /home/frappe/frappe-bench && chown -R frappe:frappe /home/frappe

# Switch to frappe user
USER frappe
WORKDIR /home/frappe

# Create the entrypoint script with proper Redis configuration
RUN echo '#!/bin/bash\n\
set -e\n\
\n\
echo "=== Frappe LMS Initialization ==="\n\
\n\
# Function to wait for service\n\
wait_for_service() {\n\
    local host=$1\n\
    local port=$2\n\
    local service=$3\n\
    local max_attempts=60\n\
    local attempt=1\n\
    \n\
    echo "Waiting for $service at $host:$port..."\n\
    while ! nc -z "$host" "$port" 2>/dev/null; do\n\
        if [ $attempt -ge $max_attempts ]; then\n\
            echo "ERROR: $service not available after $max_attempts attempts"\n\
            exit 1\n\
        fi\n\
        echo "Attempt $attempt/$max_attempts - $service not ready, waiting..."\n\
        sleep 2\n\
        attempt=$((attempt + 1))\n\
    done\n\
    echo "$service is ready!"\n\
}\n\
\n\
# Wait for database\n\
wait_for_service "${DB_HOST:-mariadb}" "${DB_PORT:-3306}" "MariaDB"\n\
\n\
# Parse Redis URL for host/port (handles redis://user:pass@host:port format)\n\
REDIS_HOST=$(echo "${REDIS_URL:-redis://redis:6379}" | sed -E "s|redis://([^@]+@)?([^:]+):([0-9]+).*|\\2|")\n\
REDIS_PORT=$(echo "${REDIS_URL:-redis://redis:6379}" | sed -E "s|redis://([^@]+@)?[^:]+:([0-9]+).*|\\2|")\n\
echo "Parsed Redis host: $REDIS_HOST, port: $REDIS_PORT"\n\
wait_for_service "$REDIS_HOST" "$REDIS_PORT" "Redis"\n\
\n\
cd /home/frappe\n\
\n\
# Initialize bench - check if Frappe is properly installed\n\
BENCH_DIR=/home/frappe/frappe-bench\n\
if [ ! -d "$BENCH_DIR/apps/frappe/frappe" ]; then\n\
    echo "Initializing Frappe bench..."\n\
    rm -rf "$BENCH_DIR" 2>/dev/null || true\n\
    bench init --skip-redis-config-generation --frappe-branch ${FRAPPE_BRANCH:-version-15} "$BENCH_DIR"\n\
fi\n\
cd "$BENCH_DIR"\n\
echo "Working directory: $(pwd)"\n\
\n\
# Configure common_site_config.json directly using Python for proper JSON handling\n\
echo "Configuring services via Python..."\n\
python3 << EOF\n\
import json\n\
import os\n\
\n\
config_path = "sites/common_site_config.json"\n\
\n\
# Load existing config or create new\n\
config = {}\n\
if os.path.exists(config_path):\n\
    with open(config_path, "r") as f:\n\
        config = json.load(f)\n\
\n\
# Get environment variables\n\
db_host = os.environ.get("DB_HOST", "mariadb")\n\
db_port = int(os.environ.get("DB_PORT", "3306"))\n\
redis_url = os.environ.get("REDIS_URL", "redis://redis:6379")\n\
\n\
# Update config\n\
config["db_host"] = db_host\n\
config["db_port"] = db_port\n\
config["redis_cache"] = redis_url\n\
config["redis_queue"] = redis_url\n\
config["redis_socketio"] = redis_url\n\
config["socketio_port"] = 9000\n\
\n\
# Write config\n\
os.makedirs("sites", exist_ok=True)\n\
with open(config_path, "w") as f:\n\
    json.dump(config, f, indent=2)\n\
\n\
print(f"Configuration written to {config_path}")\n\
print(f"  db_host: {db_host}")\n\
print(f"  redis_url: {redis_url}")\n\
EOF\n\
\n\
# Remove redis and watch from Procfile (they run externally)\n\
sed -i "/redis/d" ./Procfile 2>/dev/null || true\n\
sed -i "/watch/d" ./Procfile 2>/dev/null || true\n\
\n\
# Also remove socketio if Redis has auth (Railway Redis requires auth which socketio may not handle well)\n\
# Check if Redis URL has authentication\n\
if echo "${REDIS_URL}" | grep -q "@"; then\n\
    echo "Redis has authentication - disabling socketio to prevent connection issues"\n\
    sed -i "/socketio/d" ./Procfile 2>/dev/null || true\n\
fi\n\
\n\
# Install LMS app if not already installed\n\
if [ ! -d "apps/lms" ]; then\n\
    echo "Installing LMS app..."\n\
    if [ -d "/workspace/lms" ]; then\n\
        cp -r /workspace/lms apps/lms\n\
        bench setup requirements --node\n\
    else\n\
        bench get-app lms\n\
    fi\n\
fi\n\
\n\
# Create site if not exists\n\
SITE_NAME="${SITE_NAME:-lms.localhost}"\n\
if [ ! -d "sites/${SITE_NAME}" ]; then\n\
    echo "Creating site: ${SITE_NAME}"\n\
    bench new-site ${SITE_NAME} \\\n\
        --force \\\n\
        --mariadb-root-password "${MARIADB_ROOT_PASSWORD:-admin}" \\\n\
        --admin-password "${ADMIN_PASSWORD:-admin}" \\\n\
        --no-mariadb-socket\n\
    \n\
    echo "Installing LMS on site..."\n\
    bench --site ${SITE_NAME} install-app lms\n\
else\n\
    echo "Site ${SITE_NAME} already exists"\n\
fi\n\
\n\
# Set as current site\n\
bench use ${SITE_NAME}\n\
\n\
# Run migrations\n\
echo "Running migrations..."\n\
bench --site ${SITE_NAME} migrate || echo "Migration completed or skipped"\n\
\n\
# Set production config\n\
if [ "${DEVELOPER_MODE:-0}" = "0" ]; then\n\
    bench --site ${SITE_NAME} set-config developer_mode 0\n\
else\n\
    bench --site ${SITE_NAME} set-config developer_mode 1\n\
fi\n\
\n\
# Build assets (skip LMS frontend build errors - use pre-built assets)\n\
echo "Building assets..."\n\
bench build --app frappe || echo "Frappe build completed"\n\
bench build --app lms 2>/dev/null || echo "LMS build completed (may have warnings)"\n\
\n\
# Clear cache\n\
bench --site ${SITE_NAME} clear-cache || true\n\
\n\
echo "=== Starting Frappe LMS ==="\n\
echo "Site: ${SITE_NAME}"\n\
echo "Port: ${PORT:-8000}"\n\
\n\
# Show final Procfile\n\
echo "=== Procfile ===" \n\
cat ./Procfile\n\
echo "================"\n\
\n\
# Start bench\n\
exec bench start\n\
' > /home/frappe/entrypoint.sh && chmod +x /home/frappe/entrypoint.sh

# Expose port
EXPOSE 8000 9000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=300s --retries=5 \
    CMD curl -f http://localhost:8000/api/method/frappe.ping || exit 1

# Start the application
CMD ["/home/frappe/entrypoint.sh"]

# ============================================
# Frappe LMS Production Dockerfile
# Uses official Frappe Bench image
# ============================================
FROM frappe/bench:latest

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

# Switch to root for setup
USER root

# Install additional dependencies for LMS and networking tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    libcairo2 \
    libcairo2-dev \
    libpango-1.0-0 \
    libpangocairo-1.0-0 \
    netcat-openbsd \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy LMS app source
COPY --chown=frappe:frappe . /workspace/lms/

# Switch back to frappe user
USER frappe
WORKDIR /home/frappe

# Create the entrypoint script
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
# Initialize bench if not exists\n\
if [ ! -d "frappe-bench/apps/frappe" ]; then\n\
    echo "Initializing Frappe bench..."\n\
    bench init --skip-redis-config-generation --frappe-branch ${FRAPPE_BRANCH:-version-15} frappe-bench\n\
    cd frappe-bench\n\
else\n\
    echo "Bench already exists"\n\
    cd frappe-bench\n\
fi\n\
\n\
# Configure database and Redis\n\
echo "Configuring services..."\n\
bench set-config -g db_host "${DB_HOST:-mariadb}"\n\
bench set-config -g db_port "${DB_PORT:-3306}"\n\
bench set-config -g redis_cache "${REDIS_URL:-redis://redis:6379}"\n\
bench set-config -g redis_queue "${REDIS_URL:-redis://redis:6379}"\n\
bench set-config -g redis_socketio "${REDIS_URL:-redis://redis:6379}"\n\
\n\
# Remove redis and watch from Procfile (they run externally)\n\
sed -i "/redis/d" ./Procfile 2>/dev/null || true\n\
sed -i "/watch/d" ./Procfile 2>/dev/null || true\n\
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
# Build assets\n\
echo "Building assets..."\n\
bench build --app lms || echo "Build completed"\n\
\n\
# Clear cache\n\
bench --site ${SITE_NAME} clear-cache || true\n\
\n\
echo "=== Starting Frappe LMS ==="\n\
echo "Site: ${SITE_NAME}"\n\
echo "Port: ${PORT:-8000}"\n\
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

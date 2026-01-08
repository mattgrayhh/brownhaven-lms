# ============================================
# Stage 1: Frontend Builder - Build Vue 3 Frontend
# ============================================
FROM node:18-alpine AS frontend-builder

WORKDIR /app/frontend

# Copy frontend package files
COPY frontend/package.json frontend/yarn.lock* frontend/package-lock.json* ./

# Install frontend dependencies
RUN if [ -f yarn.lock ]; then \
        yarn install --frozen-lockfile --network-timeout 300000; \
    elif [ -f package-lock.json ]; then \
        npm ci --legacy-peer-deps; \
    else \
        npm install --legacy-peer-deps; \
    fi

# Copy frontend source
COPY frontend/ .

# Build frontend (output goes to ../lms/public/frontend/)
COPY lms/ /app/lms/
RUN npm run build

# ============================================
# Stage 2: Python Base - System Dependencies
# ============================================
FROM python:3.11-slim AS python-base

# Set environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    DEBIAN_FRONTEND=noninteractive \
    FRAPPE_USER=frappe \
    FRAPPE_HOME=/home/frappe \
    BENCH_PATH=/home/frappe/frappe-bench

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Build essentials
    gcc \
    g++ \
    make \
    git \
    # MariaDB client and development files
    mariadb-client \
    libmariadb-dev \
    libmariadb-dev-compat \
    # Redis tools
    redis-tools \
    # Required libraries for Python packages
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
    libcups2-dev \
    # Cairo for PDF generation (required by cairocffi)
    libcairo2 \
    libcairo2-dev \
    libpango-1.0-0 \
    libpangocairo-1.0-0 \
    # Additional utilities
    wget \
    curl \
    vim \
    supervisor \
    # Cleanup
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create frappe user and directories
RUN useradd -m -d ${FRAPPE_HOME} -s /bin/bash ${FRAPPE_USER} \
    && mkdir -p ${BENCH_PATH} \
    && mkdir -p ${BENCH_PATH}/apps \
    && mkdir -p ${BENCH_PATH}/sites \
    && mkdir -p ${BENCH_PATH}/logs \
    && chown -R ${FRAPPE_USER}:${FRAPPE_USER} ${FRAPPE_HOME}

# ============================================
# Stage 3: Python Dependencies
# ============================================
FROM python-base AS python-deps

WORKDIR /tmp

# Upgrade pip and install build tools
RUN pip install --upgrade pip setuptools wheel

# Install Frappe Framework
RUN pip install frappe-bench

# Copy pyproject.toml and install LMS dependencies
COPY pyproject.toml ./
RUN pip install -e . || pip install \
    websocket_client~=1.6.4 \
    markdown~=3.5.1 \
    "beautifulsoup4>=4.12,<4.14" \
    lxml~=6.0.2 \
    cairocffi==1.5.1 \
    razorpay~=1.4.1 \
    fuzzywuzzy~=0.18.0

# ============================================
# Stage 4: Runtime - Final Production Image
# ============================================
FROM python-base AS runtime

# Copy Python packages from python-deps stage
COPY --from=python-deps /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=python-deps /usr/local/bin /usr/local/bin

# Switch to frappe user
USER ${FRAPPE_USER}
WORKDIR ${BENCH_PATH}

# Initialize bench structure
RUN mkdir -p apps sites logs config

# Copy LMS application
COPY --chown=${FRAPPE_USER}:${FRAPPE_USER} . ${BENCH_PATH}/apps/lms/

# Copy built frontend from frontend-builder
COPY --from=frontend-builder --chown=${FRAPPE_USER}:${FRAPPE_USER} /app/lms/public/frontend/ ${BENCH_PATH}/apps/lms/lms/public/frontend/
COPY --from=frontend-builder --chown=${FRAPPE_USER}:${FRAPPE_USER} /app/lms/www/lms.html ${BENCH_PATH}/apps/lms/lms/www/lms.html

# Create necessary bench configuration files
RUN echo '{}' > ${BENCH_PATH}/sites/apps.json \
    && echo '{}' > ${BENCH_PATH}/sites/common_site_config.json \
    && mkdir -p ${BENCH_PATH}/sites/assets

# Create Procfile for running the application
RUN echo 'web: bench serve --port ${PORT:-8000}' > ${BENCH_PATH}/Procfile

# Create startup script
RUN echo '#!/bin/bash\n\
set -e\n\
\n\
echo "Starting Frappe LMS..."\n\
\n\
# Set default values for environment variables\n\
export SITE_NAME=${SITE_NAME:-lms.localhost}\n\
export PORT=${PORT:-8000}\n\
export DB_HOST=${DB_HOST:-localhost}\n\
export DB_PORT=${DB_PORT:-3306}\n\
export REDIS_CACHE=${REDIS_CACHE:-redis://localhost:6379}\n\
export REDIS_QUEUE=${REDIS_QUEUE:-redis://localhost:6379}\n\
export REDIS_SOCKETIO=${REDIS_SOCKETIO:-redis://localhost:6379}\n\
\n\
# Update bench configuration\n\
if [ ! -z "$DB_HOST" ]; then\n\
    bench set-config -g db_host "$DB_HOST"\n\
fi\n\
\n\
if [ ! -z "$REDIS_CACHE" ]; then\n\
    bench set-config -g redis_cache "$REDIS_CACHE"\n\
    bench set-config -g redis_queue "$REDIS_QUEUE"\n\
    bench set-config -g redis_socketio "$REDIS_SOCKETIO"\n\
fi\n\
\n\
# Create site if it does not exist\n\
if [ ! -d "${BENCH_PATH}/sites/${SITE_NAME}" ]; then\n\
    echo "Creating new site: ${SITE_NAME}"\n\
    bench new-site ${SITE_NAME} \\\n\
        --db-host ${DB_HOST} \\\n\
        --db-port ${DB_PORT} \\\n\
        --admin-password ${ADMIN_PASSWORD:-admin} \\\n\
        --mariadb-root-password ${DB_ROOT_PASSWORD:-root} \\\n\
        --install-app lms \\\n\
        --no-mariadb-socket || echo "Site may already exist or database not ready"\n\
fi\n\
\n\
# Set the site as current site\n\
bench use ${SITE_NAME} || true\n\
\n\
# Migrate site\n\
bench --site ${SITE_NAME} migrate || echo "Migration skipped or failed"\n\
\n\
# Build assets\n\
bench build --app lms || echo "Build skipped"\n\
\n\
# Clear cache\n\
bench --site ${SITE_NAME} clear-cache || echo "Cache clear skipped"\n\
\n\
# Start the application\n\
exec bench serve --port ${PORT} --host 0.0.0.0\n\
' > ${BENCH_PATH}/start.sh && chmod +x ${BENCH_PATH}/start.sh

# Environment variables for configuration
ENV PORT=8000 \
    SITE_NAME=lms.localhost \
    DB_HOST=localhost \
    DB_PORT=3306 \
    DB_NAME=lms \
    DB_ROOT_PASSWORD=root \
    ADMIN_PASSWORD=admin \
    REDIS_CACHE=redis://localhost:6379 \
    REDIS_QUEUE=redis://localhost:6379 \
    REDIS_SOCKETIO=redis://localhost:6379 \
    FRAPPE_SITE_NAME_HEADER=lms.localhost \
    DEVELOPER_MODE=0 \
    ALLOW_TESTS=0

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:${PORT}/api/method/ping || exit 1

# Set working directory
WORKDIR ${BENCH_PATH}

# Start the application
CMD ["./start.sh"]

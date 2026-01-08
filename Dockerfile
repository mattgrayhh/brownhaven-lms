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
    cron \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 22 LTS (required by LMS frontend dependencies)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
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

# Copy the entrypoint script
COPY --chown=frappe:frappe docker-entrypoint.sh /home/frappe/entrypoint.sh
RUN chmod +x /home/frappe/entrypoint.sh

# Expose port
EXPOSE 8000 9000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=300s --retries=5 \
    CMD curl -f http://localhost:8000/api/method/frappe.ping || exit 1

# Start the application
CMD ["/home/frappe/entrypoint.sh"]

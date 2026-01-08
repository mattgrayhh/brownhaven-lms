#!/bin/bash
set -e

# Production Entrypoint Script for Frappe Learning LMS on Railway
# This script handles initialization, database setup, and application startup

echo "========================================"
echo "Frappe Learning LMS - Production Startup"
echo "========================================"

# Environment variables with defaults
export DB_HOST="${DB_HOST:-mariadb}"
export DB_PORT="${DB_PORT:-3306}"
export MARIADB_ROOT_PASSWORD="${MARIADB_ROOT_PASSWORD:-admin}"
export REDIS_URL="${REDIS_URL:-redis://redis:6379}"
export SITE_NAME="${SITE_NAME:-lms.localhost}"
export ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin}"
export BENCH_DIR="${BENCH_DIR:-/home/frappe/frappe-bench}"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
}

# Function to wait for MariaDB to be ready
wait_for_mariadb() {
    log "Waiting for MariaDB at $DB_HOST:$DB_PORT..."
    local max_attempts=60
    local attempt=0
    local wait_seconds=2

    while [ $attempt -lt $max_attempts ]; do
        if mysql -h"$DB_HOST" -P"$DB_PORT" -uroot -p"$MARIADB_ROOT_PASSWORD" -e "SELECT 1" >/dev/null 2>&1; then
            log "MariaDB is ready!"
            return 0
        fi

        attempt=$((attempt + 1))
        log "MariaDB not ready yet (attempt $attempt/$max_attempts). Retrying in ${wait_seconds}s..."
        sleep $wait_seconds
    done

    error "MariaDB failed to become ready after $max_attempts attempts"
    return 1
}

# Function to wait for Redis to be ready
wait_for_redis() {
    log "Waiting for Redis at $REDIS_URL..."
    local max_attempts=60
    local attempt=0
    local wait_seconds=2

    # Extract host and port from Redis URL
    local redis_host=$(echo $REDIS_URL | sed -e 's|redis://||' -e 's|:.*||')
    local redis_port=$(echo $REDIS_URL | sed -e 's|.*:||' -e 's|/.*||')
    redis_port=${redis_port:-6379}

    while [ $attempt -lt $max_attempts ]; do
        if redis-cli -h "$redis_host" -p "$redis_port" ping >/dev/null 2>&1; then
            log "Redis is ready!"
            return 0
        fi

        attempt=$((attempt + 1))
        log "Redis not ready yet (attempt $attempt/$max_attempts). Retrying in ${wait_seconds}s..."
        sleep $wait_seconds
    done

    error "Redis failed to become ready after $max_attempts attempts"
    return 1
}

# Function to initialize Frappe bench
initialize_bench() {
    if [ ! -d "$BENCH_DIR" ] || [ ! -f "$BENCH_DIR/config/common_site_config.json" ]; then
        log "Initializing Frappe bench..."

        # Create parent directory if it doesn't exist
        mkdir -p "$(dirname "$BENCH_DIR")"

        # Initialize bench
        bench init "$BENCH_DIR" --frappe-branch version-14 --python python3.10 || {
            error "Failed to initialize bench"
            return 1
        }

        log "Bench initialized successfully"
    else
        log "Bench already exists at $BENCH_DIR"
    fi

    cd "$BENCH_DIR"
    return 0
}

# Function to configure database and redis
configure_services() {
    log "Configuring database and Redis connections..."

    cd "$BENCH_DIR"

    # Configure MariaDB
    bench set-config -g db_host "$DB_HOST" || {
        error "Failed to set MariaDB host"
        return 1
    }

    bench set-config -g db_port "$DB_PORT" || {
        error "Failed to set MariaDB port"
        return 1
    }

    # Configure Redis
    bench set-config -g redis_cache "$REDIS_URL" || {
        error "Failed to set Redis cache"
        return 1
    }

    bench set-config -g redis_queue "$REDIS_URL" || {
        error "Failed to set Redis queue"
        return 1
    }

    bench set-config -g redis_socketio "$REDIS_URL" || {
        error "Failed to set Redis socketio"
        return 1
    }

    log "Service configuration completed"
    return 0
}

# Function to get or create the LMS app
setup_lms_app() {
    cd "$BENCH_DIR"

    if [ ! -d "$BENCH_DIR/apps/lms" ]; then
        log "Getting LMS app..."
        bench get-app lms || {
            error "Failed to get LMS app"
            return 1
        }
        log "LMS app downloaded successfully"
    else
        log "LMS app already exists"
    fi

    return 0
}

# Function to create or verify site
setup_site() {
    cd "$BENCH_DIR"

    if [ ! -d "$BENCH_DIR/sites/$SITE_NAME" ]; then
        log "Creating new site: $SITE_NAME"

        bench new-site "$SITE_NAME" \
            --mariadb-root-password "$MARIADB_ROOT_PASSWORD" \
            --admin-password "$ADMIN_PASSWORD" \
            --no-mariadb-socket || {
            error "Failed to create site"
            return 1
        }

        log "Site created successfully"
    else
        log "Site $SITE_NAME already exists"
    fi

    return 0
}

# Function to install LMS app on site
install_lms() {
    cd "$BENCH_DIR"

    log "Checking if LMS app is installed on site..."

    # Check if app is already installed
    if bench --site "$SITE_NAME" list-apps | grep -q "lms"; then
        log "LMS app already installed on site"
    else
        log "Installing LMS app on site..."
        bench --site "$SITE_NAME" install-app lms || {
            error "Failed to install LMS app"
            return 1
        }
        log "LMS app installed successfully"
    fi

    return 0
}

# Function to run migrations
run_migrations() {
    cd "$BENCH_DIR"

    log "Running database migrations..."
    bench --site "$SITE_NAME" migrate || {
        error "Failed to run migrations"
        return 1
    }
    log "Migrations completed successfully"

    return 0
}

# Function to set production configuration
set_production_config() {
    cd "$BENCH_DIR"

    log "Setting production configuration..."

    # Disable developer mode
    bench --site "$SITE_NAME" set-config developer_mode 0 || {
        error "Failed to disable developer mode"
        return 1
    }

    # Enable production settings
    bench --site "$SITE_NAME" set-config maintenance_mode 0 || {
        log "Warning: Failed to disable maintenance mode"
    }

    # Set server script enabled (useful for LMS)
    bench --site "$SITE_NAME" set-config server_script_enabled 1 || {
        log "Warning: Failed to enable server scripts"
    }

    log "Production configuration set"
    return 0
}

# Function to clear cache
clear_cache() {
    cd "$BENCH_DIR"

    log "Clearing cache..."
    bench --site "$SITE_NAME" clear-cache || {
        log "Warning: Failed to clear cache"
    }

    bench --site "$SITE_NAME" clear-website-cache || {
        log "Warning: Failed to clear website cache"
    }

    log "Cache cleared"
    return 0
}

# Function to start the application
start_application() {
    cd "$BENCH_DIR"

    log "Starting Frappe application in production mode..."

    # Build assets for production
    log "Building production assets..."
    bench build --production --app lms || {
        log "Warning: Failed to build production assets"
    }

    # Start using gunicorn for production
    log "Starting gunicorn server..."

    # Use bench serve for production (which uses gunicorn internally)
    # Or start gunicorn directly
    exec bench serve \
        --port "${PORT:-8000}" \
        --noreload \
        --nothreading
}

# Main execution flow
main() {
    log "Starting production deployment..."

    # Wait for services
    wait_for_mariadb || exit 1
    wait_for_redis || exit 1

    # Initialize bench if needed
    initialize_bench || exit 1

    # Configure services
    configure_services || exit 1

    # Setup LMS app
    setup_lms_app || exit 1

    # Setup site
    setup_site || exit 1

    # Install LMS
    install_lms || exit 1

    # Run migrations
    run_migrations || exit 1

    # Set production config
    set_production_config || exit 1

    # Clear cache
    clear_cache || exit 1

    log "Initialization completed successfully!"
    log "========================================"

    # Start application
    start_application
}

# Run main function
main

# Docker Quick Start Guide

## Local Testing

### Using Docker Compose (Recommended)

```bash
# Build and start all services
docker-compose -f docker-compose.railway.yml up --build

# Access the application
# Navigate to: http://localhost:8000
# Username: Administrator
# Password: admin
```

### Using Docker Only

```bash
# Build the image
docker build -t frappe-lms:latest .

# Run MariaDB
docker run -d --name lms-mariadb \
  -e MYSQL_ROOT_PASSWORD=rootpassword \
  -e MYSQL_DATABASE=lms \
  -p 3306:3306 \
  mariadb:10.11

# Run Redis
docker run -d --name lms-redis \
  -p 6379:6379 \
  redis:7-alpine

# Run LMS (wait for DB and Redis to be ready)
docker run -d --name frappe-lms \
  -p 8000:8000 \
  -e SITE_NAME=lms.localhost \
  -e DB_HOST=host.docker.internal \
  -e DB_ROOT_PASSWORD=rootpassword \
  -e REDIS_CACHE=redis://host.docker.internal:6379 \
  -e REDIS_QUEUE=redis://host.docker.internal:6379 \
  -e REDIS_SOCKETIO=redis://host.docker.internal:6379 \
  -e ADMIN_PASSWORD=admin \
  frappe-lms:latest
```

## Railway Deployment

### Prerequisites
1. Railway account at https://railway.app
2. GitHub repository connected to Railway

### Quick Deploy Steps

1. **Push to GitHub**
   ```bash
   git add Dockerfile .dockerignore railway.json RAILWAY_DEPLOYMENT.md
   git commit -m "Add Railway deployment configuration"
   git push origin main
   ```

2. **Create Railway Project**
   - Go to Railway dashboard
   - Click "New Project"
   - Select "Deploy from GitHub repo"

3. **Add Services**
   - Add MariaDB database service
   - Add Redis service
   - LMS service (your app) will be added automatically

4. **Configure Environment Variables**
   ```env
   SITE_NAME=${{RAILWAY_PUBLIC_DOMAIN}}
   DB_HOST=${{MariaDB.MYSQLHOST}}
   DB_PORT=${{MariaDB.MYSQLPORT}}
   DB_ROOT_PASSWORD=${{MariaDB.MYSQL_ROOT_PASSWORD}}
   REDIS_CACHE=redis://${{Redis.REDIS_URL}}
   REDIS_QUEUE=redis://${{Redis.REDIS_URL}}
   REDIS_SOCKETIO=redis://${{Redis.REDIS_URL}}
   ADMIN_PASSWORD=your-secure-password
   ```

5. **Deploy**
   - Railway will automatically build using the Dockerfile
   - First deployment takes 5-10 minutes
   - Access via Railway-provided domain

## Dockerfile Features

### Multi-Stage Build
- **Stage 1**: Builds Vue 3 frontend (Node.js 18)
- **Stage 2**: Sets up system dependencies
- **Stage 3**: Installs Python dependencies
- **Stage 4**: Creates final production image

### Optimizations
- Uses Alpine Linux for frontend build (smaller size)
- Multi-stage build reduces final image size
- .dockerignore excludes unnecessary files
- Layer caching for faster rebuilds

### Security
- Non-root user (frappe)
- Minimal system packages
- No development tools in final image
- Environment-based configuration

### Production Ready
- Health checks configured
- Automatic site initialization
- Graceful error handling
- Logging enabled

## Environment Variables Reference

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `SITE_NAME` | Yes | lms.localhost | Your domain name |
| `DB_HOST` | Yes | localhost | Database host |
| `DB_PORT` | No | 3306 | Database port |
| `DB_ROOT_PASSWORD` | Yes | root | Database password |
| `REDIS_CACHE` | Yes | redis://localhost:6379 | Redis cache URL |
| `REDIS_QUEUE` | Yes | redis://localhost:6379 | Redis queue URL |
| `REDIS_SOCKETIO` | Yes | redis://localhost:6379 | Redis socketio URL |
| `ADMIN_PASSWORD` | Yes | admin | Admin user password |
| `PORT` | No | 8000 | Application port |
| `DEVELOPER_MODE` | No | 0 | Enable dev mode (0 or 1) |

## Troubleshooting

### Build Fails
```bash
# Check Docker logs
docker-compose -f docker-compose.railway.yml logs lms

# Rebuild without cache
docker-compose -f docker-compose.railway.yml build --no-cache
```

### Site Creation Fails
- Ensure database is running and accessible
- Check database credentials
- Verify database permissions

### Frontend Not Loading
- Check if frontend build completed in logs
- Verify assets directory permissions
- Clear browser cache

### Can't Connect to Database
- Check DB_HOST is correct
- Verify database service is running
- Test database connection:
  ```bash
  docker exec -it lms-mariadb mysql -u root -p
  ```

## Useful Commands

```bash
# View logs
docker-compose -f docker-compose.railway.yml logs -f lms

# Access container shell
docker exec -it frappe-lms bash

# Restart services
docker-compose -f docker-compose.railway.yml restart

# Stop all services
docker-compose -f docker-compose.railway.yml down

# Remove volumes (clean slate)
docker-compose -f docker-compose.railway.yml down -v

# Check running containers
docker ps

# View image size
docker images frappe-lms
```

## File Structure

```
/home/user/brownhaven-lms/
├── Dockerfile                      # Multi-stage production Dockerfile
├── .dockerignore                   # Excludes unnecessary files from build
├── railway.json                    # Railway configuration
├── RAILWAY_DEPLOYMENT.md          # Comprehensive Railway guide
├── docker-compose.railway.yml     # Local testing environment
└── DOCKER_QUICK_START.md          # This file
```

## Next Steps

1. **Local Testing**: Test with docker-compose
2. **Railway Deploy**: Follow RAILWAY_DEPLOYMENT.md
3. **Configure**: Set up email, domain, etc.
4. **Monitor**: Check logs and health checks
5. **Scale**: Adjust resources as needed

## Support

- **Frappe Docs**: https://frappeframework.com/docs
- **Railway Docs**: https://docs.railway.app
- **LMS Repo**: https://github.com/frappe/lms
- **Issues**: Create issue in GitHub repository

---

For detailed Railway deployment instructions, see [RAILWAY_DEPLOYMENT.md](./RAILWAY_DEPLOYMENT.md)

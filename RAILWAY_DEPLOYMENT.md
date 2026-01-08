# Railway Deployment Guide for Frappe Learning LMS

This guide provides step-by-step instructions for deploying Frappe Learning LMS on Railway using Docker Compose.

## Prerequisites

Before you begin, ensure you have:

- A [Railway](https://railway.app) account (sign up for free)
- A GitHub account with this repository forked or accessible
- Railway CLI installed (optional, for advanced management)
  ```bash
  npm install -g @railway/cli
  ```
- Basic understanding of Docker and environment variables

## Quick Start

Follow these steps to deploy Frappe Learning LMS on Railway:

### 1. Connect Your Repository

1. Log in to [Railway](https://railway.app)
2. Click **"New Project"**
3. Select **"Deploy from GitHub repo"**
4. Authorize Railway to access your GitHub repositories
5. Select your Frappe Learning LMS repository

### 2. Configure Railway for Docker Compose

Railway supports Docker Compose natively. Your project will automatically detect the `docker-compose.yml` file in the `/docker` directory.

1. In your Railway project dashboard, click on **"Settings"**
2. Under **"Build"**, set the **Root Directory** to `/docker` (if your docker-compose.yml is in the docker folder)
3. Railway will automatically detect and use your Docker Compose configuration

### 3. Set Up Environment Variables

Go to your Railway project **Variables** section and add the required environment variables (see the **Environment Variables** section below for details).

### 4. Deploy the Services

1. Railway will automatically deploy your services based on the docker-compose.yml configuration
2. Monitor the deployment logs in the Railway dashboard
3. Wait for all services (app, mariadb, redis) to be healthy and running

### 5. Access Your Application

Once deployed, Railway will provide a public URL for your application. You can access it from the **"Deployments"** tab in your project dashboard.

## Environment Variables

Configure these variables in Railway's **Variables** section for your project. You can copy values from `.env.example` as a starting point.

### Required Variables

| Variable | Description | Example Value |
|----------|-------------|---------------|
| `MARIADB_ROOT_PASSWORD` | MariaDB root password (use strong password) | `SecureRootPass123!` |
| `MARIADB_DATABASE` | Database name for the LMS | `lms` |
| `MARIADB_USER` | Database user for application | `frappe` |
| `MARIADB_PASSWORD` | Password for database user | `SecureDBPass123!` |
| `DB_HOST` | Database service hostname | `mariadb` (Railway internal DNS) |
| `DB_PORT` | Database port | `3306` |
| `REDIS_URL` | Redis connection URL | `redis://redis:6379` |
| `SITE_NAME` | Your Railway domain or custom domain | `your-app.railway.app` |
| `ADMIN_PASSWORD` | Administrator account password | `YourAdminPass123!` |
| `FRAPPE_DEVELOPER_MODE` | Developer mode (0 for production, 1 for dev) | `0` |

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PAYMENT_GATEWAY` | Payment gateway provider | `Razorpay` |
| `DEFAULT_CURRENCY` | Default currency for payments | `USD` |
| `RAZORPAY_KEY_ID` | Razorpay API Key ID | - |
| `RAZORPAY_KEY_SECRET` | Razorpay API Key Secret | - |
| `APPLY_GST` | Apply GST on payments (1=yes, 0=no) | `0` |
| `UNSPLASH_ACCESS_KEY` | Unsplash API key for images | - |
| `LIVECODE_URL` | LiveCode server for code execution | `https://falcon.frappe.io/` |
| `MAIL_SERVER` | SMTP server hostname | - |
| `MAIL_PORT` | SMTP server port | `587` |
| `MAIL_LOGIN` | Email account username | - |
| `MAIL_PASSWORD` | Email account password | - |
| `MAIL_USE_TLS` | Use TLS encryption (1=yes, 0=no) | `1` |
| `WORKERS` | Number of background workers | `2` |
| `GUNICORN_WORKERS` | Number of Gunicorn web workers | `4` |

**Important:** For production deployments, always set `FRAPPE_DEVELOPER_MODE=0` for better performance and security.

## Services Overview

Your Frappe Learning LMS deployment consists of three interconnected services:

### 1. App Service (Frappe)

- **Image:** `frappe/bench:latest`
- **Purpose:** Runs the Frappe Framework and LMS application
- **Ports:** 8000 (web interface), 9000 (socketio)
- **Key Features:**
  - Handles web requests and business logic
  - Manages background jobs and scheduled tasks
  - Serves the LMS user interface
  - Connects to MariaDB and Redis

### 2. MariaDB Service

- **Image:** `mariadb:10.8`
- **Purpose:** Primary database for storing all LMS data
- **Port:** 3306
- **Configuration:**
  - Character set: `utf8mb4`
  - Collation: `utf8mb4_unicode_ci`
  - Persistent storage via Railway volumes
- **Stores:** Courses, users, batches, assessments, enrollment data, etc.

### 3. Redis Service

- **Image:** `redis:alpine`
- **Purpose:** In-memory data store for caching and message queuing
- **Port:** 6379
- **Uses:**
  - Session management
  - Caching for improved performance
  - Background job queuing
  - Real-time socketio communication

## Database Setup

### Automatic Configuration

The MariaDB database is automatically configured during the initial deployment:

1. **Database Creation:** A database is created using `MARIADB_DATABASE` variable
2. **User Setup:** A user is created with credentials from `MARIADB_USER` and `MARIADB_PASSWORD`
3. **Character Encoding:** UTF-8 support enabled with `utf8mb4` character set
4. **Bench Integration:** The app automatically connects to MariaDB using Railway's internal DNS

### Accessing the Database

**From within Railway:**

Use Railway's internal service networking:
- Host: `mariadb` (service name)
- Port: `3306`
- Username: Value of `MARIADB_USER`
- Password: Value of `MARIADB_PASSWORD`

**Using Railway CLI:**

```bash
# Connect to your database service
railway connect mariadb

# Or run MySQL commands directly
railway run mysql -h mariadb -u frappe -p lms
```

**From a Database Client:**

Railway can expose a public TCP proxy for external database access:
1. Go to your MariaDB service in Railway dashboard
2. Navigate to **"Settings" > "Networking"**
3. Click **"Create TCP Proxy"**
4. Use the provided host and port with your database client

**Note:** For security, only enable TCP proxy when needed and restrict access using Railway's security features.

## Initial Setup

After your first deployment, follow these steps to initialize your LMS:

### 1. Wait for Initialization

The initial setup takes approximately 5-10 minutes:
- Frappe bench initialization
- App installation
- Site creation
- Database migration

Monitor progress in Railway's deployment logs.

### 2. First-Time Access

Once deployment is complete:

1. Navigate to your Railway-provided URL (e.g., `https://your-app.railway.app`)
2. You may see a setup wizard on first access
3. Use the following default credentials to complete setup:
   - **Username:** `Administrator`
   - **Password:** Value of `ADMIN_PASSWORD` environment variable (or `admin` if not set)

### 3. Post-Setup Configuration

After logging in as Administrator:

1. **Update Site Name:**
   - Go to **LMS Settings**
   - Update site name to match your Railway domain

2. **Configure Email Settings** (recommended):
   - Navigate to **Settings > Email Domain**
   - Add your SMTP configuration for password resets and notifications

3. **Set Up Your First Course:**
   - Go to **LMS > Course**
   - Click **"New"** to create your first course

4. **Change Default Password:**
   - Click on your profile
   - Select **"Update Password"**
   - Set a strong password for the Administrator account

## Accessing the Application

### Web Interface

Your LMS is accessible at the Railway-provided domain or your custom domain:

```
https://your-project-name.railway.app/lms
```

### Default Admin Credentials

- **Username:** `Administrator`
- **Password:** Value of `ADMIN_PASSWORD` environment variable
  - If not set during deployment: `admin` (change immediately!)

**Security Recommendation:** Change the default administrator password immediately after first login.

### Initial Configuration in LMS Settings

Navigate to **LMS Settings** to configure:

1. **Site Information:**
   - Site name and description
   - Logo and branding
   - Contact information

2. **Course Settings:**
   - Enable/disable self-enrollment
   - Default course visibility
   - Certificate templates

3. **Batch Settings:**
   - Batch creation permissions
   - Assessment settings
   - Live class integration (Zoom)

4. **Payment Settings:**
   - Enable paid courses
   - Configure Razorpay (if using payments)
   - Set default currency

5. **Email Notifications:**
   - Course enrollment confirmations
   - Assessment reminders
   - Certificate notifications

## Scaling

Railway makes it easy to scale your Frappe Learning LMS as your user base grows.

### Vertical Scaling (Resource Scaling)

Increase resources for existing services:

1. Navigate to your service in Railway dashboard
2. Click on **"Settings" > "Resources"**
3. Adjust CPU and Memory allocations
4. Railway will automatically restart the service

**Recommended allocations:**

| Deployment Size | App CPU | App RAM | MariaDB RAM | Redis RAM |
|----------------|---------|---------|-------------|-----------|
| Small (< 100 users) | 1 vCPU | 1 GB | 512 MB | 256 MB |
| Medium (100-500 users) | 2 vCPU | 2 GB | 1 GB | 512 MB |
| Large (500+ users) | 4 vCPU | 4 GB | 2 GB | 1 GB |

### Horizontal Scaling (Worker Scaling)

Adjust the number of background workers and web workers:

1. Update environment variables in Railway:
   - `WORKERS`: Number of background job workers (default: 2)
   - `GUNICORN_WORKERS`: Number of web request workers (default: 4)

2. **Recommended formula:**
   - Background workers: 1-2 per vCPU
   - Gunicorn workers: (2 × CPU cores) + 1

3. Redeploy after changing these variables

### Database Scaling

For larger deployments:

1. **Enable Connection Pooling:** Configure in Frappe site config
2. **Optimize Queries:** Review slow query logs
3. **Add Read Replicas:** (requires custom configuration)
4. **Use Railway's Database Scaling:** Upgrade to higher-tier database plans

### Monitoring and Performance

Monitor your application's performance:
- Use Railway's built-in metrics dashboard
- Check deployment logs for errors
- Monitor database query performance
- Track Redis memory usage

## Troubleshooting

### Database Connection Issues

**Symptom:** App fails to connect to database, shows connection errors

**Solutions:**

1. **Verify database service is running:**
   ```bash
   railway status
   ```

2. **Check environment variables:**
   - Ensure `DB_HOST=mariadb` (Railway internal DNS)
   - Verify `DB_PORT=3306`
   - Confirm `MARIADB_USER` and `MARIADB_PASSWORD` match

3. **Check database logs:**
   - Navigate to MariaDB service in Railway
   - View deployment logs for errors

4. **Restart services in order:**
   ```bash
   # Using Railway CLI
   railway restart mariadb
   railway restart frappe
   ```

### Redis Connection Issues

**Symptom:** Caching errors, background jobs not processing

**Solutions:**

1. **Verify Redis URL format:**
   ```
   REDIS_URL=redis://redis:6379
   ```

2. **Check Redis service status:**
   - Ensure Redis service is healthy in Railway dashboard

3. **Clear Redis cache:**
   ```bash
   railway run bench --site [site-name] clear-cache
   ```

4. **Restart Redis and app services:**
   ```bash
   railway restart redis
   railway restart frappe
   ```

### Site Not Loading

**Symptom:** 404 errors, blank page, or "Site not found"

**Solutions:**

1. **Verify SITE_NAME matches your domain:**
   ```
   SITE_NAME=your-app.railway.app
   ```

2. **Check if site was created:**
   ```bash
   railway run bench --site all list-apps
   ```

3. **Access correct URL path:**
   - Ensure you're accessing `/lms` endpoint: `https://your-app.railway.app/lms`

4. **Rebuild the site:**
   ```bash
   railway run bench --site [site-name] migrate
   railway run bench --site [site-name] build
   ```

### Permission Errors

**Symptom:** 500 errors, file permission issues in logs

**Solutions:**

1. **Check file permissions in volumes:**
   - Railway volumes should maintain proper permissions
   - Review deployment logs for permission denied errors

2. **Restart the app service:**
   ```bash
   railway restart frappe
   ```

3. **Clear cache and rebuild:**
   ```bash
   railway run bench --site [site-name] clear-cache
   railway run bench --site [site-name] build
   ```

### General Debugging Steps

1. **View deployment logs:**
   - Check Railway dashboard logs for all services
   - Look for error messages during initialization

2. **Enable verbose logging:**
   - Set `FRAPPE_DEVELOPER_MODE=1` temporarily
   - Review detailed error traces
   - Remember to set back to `0` for production

3. **Verify all services are running:**
   ```bash
   railway status
   ```

4. **Check Railway service health:**
   - Ensure all services show "Active" status
   - Review health check logs

5. **Contact support:**
   - [Railway Discord](https://discord.gg/railway)
   - [Frappe Community Forum](https://discuss.frappe.io/c/lms/70)

## Backup & Restore

Regular backups are essential for protecting your LMS data.

### Manual Database Backup

**Using Railway CLI:**

```bash
# Export database to SQL file
railway run mysqldump -h mariadb -u frappe -p lms > lms_backup_$(date +%Y%m%d).sql

# Or use Frappe's backup command
railway run bench --site [site-name] backup --with-files
```

**Files are saved to:**
```
~/frappe-bench/sites/[site-name]/private/backups/
```

### Automated Backups

**Set up automated backups using Railway Cron or external service:**

1. **Create a backup script** (`backup.sh`):
   ```bash
   #!/bin/bash
   DATE=$(date +%Y%m%d_%H%M%S)
   bench --site [site-name] backup --with-files
   echo "Backup completed: $DATE"
   ```

2. **Use Railway Cron** (if available in your plan) or external cron service

3. **Store backups externally:**
   - Upload to S3, Google Cloud Storage, or Backblaze
   - Use Railway's volume snapshots (if available)

### Restore from Backup

**Restore database:**

```bash
# Using Railway CLI
railway run mysql -h mariadb -u frappe -p lms < lms_backup_20260108.sql

# Or using Frappe restore command
railway run bench --site [site-name] restore [path-to-backup-file]
```

**Restore files:**

```bash
# Restore private files
railway run bench --site [site-name] restore \
  --with-private-files [path-to-private-files-backup] \
  --with-public-files [path-to-public-files-backup]
```

### Backup Best Practices

1. **Frequency:** Daily backups for active sites, weekly for development
2. **Retention:** Keep at least 7 daily backups and 4 weekly backups
3. **Off-site Storage:** Always store backups outside Railway
4. **Test Restores:** Regularly test backup restoration process
5. **Document:** Keep a record of backup locations and procedures

### Railway Volume Snapshots

Railway may offer volume snapshots (check your plan):

1. Navigate to your service in Railway dashboard
2. Go to **"Data" > "Volumes"**
3. Create manual snapshots before major changes
4. Configure automatic snapshot schedules if available

## Custom Domain

Configure a custom domain for your Frappe Learning LMS deployment.

### 1. Configure Domain in Railway

1. Navigate to your **Frappe service** in Railway dashboard
2. Click on **"Settings" > "Domains"**
3. Click **"Add Custom Domain"**
4. Enter your domain name (e.g., `learn.yourdomain.com`)
5. Railway will provide DNS configuration instructions

### 2. Update DNS Records

Add the following DNS records at your domain registrar:

**For root domain (example.com):**
```
Type: A
Name: @
Value: [Railway IP provided]
```

**For subdomain (learn.example.com):**
```
Type: CNAME
Name: learn
Value: [Railway CNAME provided]
```

**SSL/TLS:** Railway automatically provisions SSL certificates via Let's Encrypt.

### 3. Update Environment Variables

Update your site configuration in Railway:

```
SITE_NAME=learn.yourdomain.com
```

Redeploy your application after updating this variable.

### 4. Update Site Config in Frappe

After deployment, update the site configuration:

```bash
# Using Railway CLI
railway run bench --site lms.localhost rename-site learn.yourdomain.com

# Or update site config directly
railway run bench --site learn.yourdomain.com set-config host_name learn.yourdomain.com
```

### 5. Verify Domain Configuration

1. Wait for DNS propagation (can take up to 48 hours, usually faster)
2. Check DNS propagation: `nslookup learn.yourdomain.com`
3. Access your site at `https://learn.yourdomain.com/lms`
4. Verify SSL certificate is active (should show padlock icon)

### Multiple Domains

To serve multiple domains from one deployment:

1. Add all domains in Railway settings
2. Configure Frappe to accept multiple hosts
3. Update site config to include all allowed hosts

### Troubleshooting Domain Issues

- **DNS not resolving:** Wait for propagation, check DNS records
- **SSL errors:** Ensure DNS points to Railway, wait for cert provisioning
- **Site not loading:** Verify `SITE_NAME` environment variable matches domain
- **Mixed content warnings:** Ensure all assets use HTTPS

---

## Additional Resources

- **Frappe LMS Documentation:** https://docs.frappe.io/learning
- **Frappe Framework Docs:** https://frappeframework.com/docs
- **Railway Documentation:** https://docs.railway.app
- **Community Support:**
  - [Telegram Public Group](https://t.me/frappelms)
  - [Discuss Forum](https://discuss.frappe.io/c/lms/70)
- **GitHub Repository:** https://github.com/frappe/lms

## Support and Contributing

If you encounter issues not covered in this guide:

1. Check the [GitHub Issues](https://github.com/frappe/lms/issues)
2. Ask in the [Community Forum](https://discuss.frappe.io/c/lms/70)
3. Join the [Telegram Group](https://t.me/frappelms)
4. For Railway-specific issues, visit [Railway Discord](https://discord.gg/railway)

**Happy Learning!**

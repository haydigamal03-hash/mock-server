# TRON Dashboard - Installation & Configuration Guide

## System Requirements

- **Node.js**: v16 or higher
- **npm**: v7 or higher
- **Operating System**: Linux, macOS, Windows
- **Memory**: 512MB minimum
- **Storage**: 1GB for database and logs
- **Port**: 3000 (configurable)

## Installation

### 1. Clone Repository
```bash
git clone <repository-url>
cd mock-server
```

### 2. Install Dependencies
```bash
npm install
```

### 3. Create .env File

**CRITICAL**: Never commit .env to version control

```bash
cp .env.example .env
```

Edit `.env` with your settings:
```bash
NODE_ENV=development
PORT=3000
HOST=localhost
SESSION_SECRET=<generate-secure-random-key>
```

**Generate a secure SESSION_SECRET**:
```bash
# Linux/macOS
openssl rand -base64 32

# Windows (PowerShell)
[Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((New-Guid).ToString()))
```

### 4. Initialize Application

**IMPORTANT**: This must be run on the actual server, NOT during Docker builds

```bash
npm run init
```

This script:
- Generates master encryption key (stored in `.master-key`)
- Initializes SQLite database
- Creates default admin user
- Sets up 30-day trial license
- Validates all configurations

### 5. Start Application

**Development**:
```bash
npm run dev
```

**Production**:
```bash
NODE_ENV=production npm start
```

Server runs on: `http://localhost:3000`

## First-Time Login

1. Navigate to `http://localhost:3000`
2. Login with credentials:
   - **Username**: `admin`
   - **Password**: `admin123`
3. **IMMEDIATELY** change the admin password
4. Create additional user accounts as needed

## Directory Structure

```
mock-server/
├── src/
│   ├── index.js                 # Application entry point
│   ├── middleware/
│   │   ├── security.js          # MILD security middleware
│   │   └── route-protection.js  # Route protection middleware
│   ├── routes/
│   │   ├── auth.js              # Authentication routes
│   │   ├── admin-protected.js   # Admin-only routes
│   │   └── user-protected.js    # User routes
│   ├── config/
│   │   ├── database.js          # Database configuration
│   │   └── encryption.js        # Encryption configuration
│   ├── public/
│   │   └── login.html           # Login page
│   └── data/
│       └── encryption.key       # Encryption key (git-ignored)
├── docs/
│   ├── INSTALLATION_GUIDE.md    # This file
│   ├── MILD-SECURITY-FRAMEWORK.md # Security documentation
├── scripts/
│   └── init.js                  # Initialization script
├── .env                         # Environment (NOT committed)
├── .env.example                 # Environment template
├── .gitignore                   # Git ignore rules
├── package.json                 # Dependencies
└── README.md                    # Documentation
```

## Security Configuration

### 1. Master Encryption Key
- Generated during `npm run init`
- Stored in `.master-key` (in `.gitignore`)
- Never committed to repository
- Used for AES-256-GCM encryption

### 2. Session Management
- HttpOnly cookies (no JavaScript access)
- Secure flag (HTTPS only in production)
- SameSite=Strict (CSRF protection)
- 24-hour expiration
- No token in URLs

### 3. Database Encryption
- Passwords: PBKDF2 hashing (100,000 iterations)
- Private keys: AES-256-GCM encrypted
- Wallet data: AES-256-GCM encrypted
- All encryption uses secure master key

### 4. Route Protection
- All non-login routes require session
- Role-based access control (admin/user)
- Resource ownership verification (IDOR prevention)
- Input sanitization and validation
- SQL injection prevention (parameterized queries)

## Production Deployment

### 1. Environment Setup
```bash
# Update .env for production
NODE_ENV=production
PORT=3000
HOST=0.0.0.0
SESSION_SECRET=<strong-random-key>
```

### 2. System Requirements
- Firewall: Allow port 3000 (or configured PORT)
- Reverse proxy: Nginx/Apache (recommended)
- SSL/TLS: HTTPS certificate required
- Node process manager: PM2 or systemd

### 3. Start with PM2
```bash
# Install PM2
npm install -g pm2

# Start application
pm2 start src/index.js --name "tron-dashboard"

# Enable auto-restart on reboot
pm2 startup
pm2 save
```

### 4. Nginx Configuration (Example)
```nginx
upstream tron_app {
  server localhost:3000;
}

server {
  listen 443 ssl http2;
  server_name yourdomain.com;

  ssl_certificate /path/to/cert.pem;
  ssl_certificate_key /path/to/key.pem;

  location / {
    proxy_pass http://tron_app;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
  }
}
```

## Troubleshooting

### Master Key Not Found
```
Error: Master key not found
```
**Solution**: Run `npm run init` to generate master key

### Database Error
```
Error: Database connection failed
```
**Solution**: Ensure `data/` directory exists and is writable

### Session Secret Not Set
```
Error: SESSION_SECRET environment variable is not set
```
**Solution**: Create `.env` file with `SESSION_SECRET` value

### Port Already in Use
```
Error: listen EADDRINUSE: address already in use :::3000
```
**Solution**: Change PORT in .env or stop other process on port 3000

## Monitoring & Maintenance

### Regular Tasks
- Monitor disk space for database growth
- Review security logs weekly
- Backup database regularly
- Update dependencies monthly
- Rotate SESSION_SECRET quarterly

### Backup Strategy
```bash
# Backup database
cp src/data/app.db src/data/app.db.backup.$(date +%Y%m%d)

# Backup master key (keep separate from code)
cp .master-key /secure/location/.master-key.backup
```

## Support

For issues or questions:
1. Check logs: `npm run dev` (development logs to console)
2. Review SECURITY.md for security guidelines
3. Check INSTALLATION_GUIDE.md for troubleshooting

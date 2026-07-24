# TRON Dashboard - MILD Security Framework

## Overview

TRON Dashboard is an enterprise-grade web application featuring the **MILD Security Framework** (Monitored Intelligent Layered Defense) - a comprehensive 7-layer security architecture.

## Features

- ✅ 7-Layer Security Architecture
- ✅ Real-time Threat Detection
- ✅ Adaptive Response System
- ✅ AES-256-GCM Encryption
- ✅ SQL Injection Prevention
- ✅ XSS Protection
- ✅ CSRF Protection
- ✅ Rate Limiting
- ✅ Session Management
- ✅ Comprehensive Audit Logging

## Quick Start

### Prerequisites
- Node.js 16+
- npm 7+

### Installation

```bash
# Clone and setup
git clone https://github.com/haydigamal03-hash/mock-server.git
cd mock-server

# Install dependencies
npm install

# Initialize
npm run init

# Create .env file
cp .env.example .env

# Start development server
npm run dev
```

Server runs on: `http://localhost:3000`

## Default Credentials

**⚠️ Change these immediately after first login!**

- **Admin**: username: `admin` | password: `admin123`
- **User**: username: `user` | password: `user123`

## Project Structure

```
mock-server/
├── src/
│   ├── index.js              # Application entry point
│   ├── middleware/           # Security middleware
│   ├── routes/              # API routes
│   ├── config/              # Configuration
│   ├── public/              # Frontend assets
│   └── data/                # Database (runtime)
├── docs/                    # Documentation
├── scripts/                 # Utility scripts
├── package.json
├── .env.example
└── README.md
```

## Documentation

- [Installation Guide](./docs/INSTALLATION_GUIDE.md)
- [MILD Security Framework](./docs/MILD-SECURITY-FRAMEWORK.md)

## Security Highlights

### 7 Layers of Defense

1. **Network Security** - Port and protocol validation
2. **Transport Security** - HTTPS enforcement
3. **Application Security** - Input sanitization
4. **Authentication & Authorization** - Session and role-based access
5. **Business Logic** - Rate limiting and operation validation
6. **Data Layer** - Encryption and audit logging
7. **Response Security** - Output encoding and error filtering

### Built-in Protections

- SQL Injection Prevention
- XSS Attack Mitigation
- Command Injection Detection
- Template Injection Prevention
- Header Injection Detection
- CSRF Token Validation
- Session Fixation Prevention
- Directory Traversal Prevention

## Environment Variables

```bash
PORT=3000                           # Server port
NODE_ENV=development               # Environment
SESSION_SECRET=<secure-key>       # Session encryption (REQUIRED)
```

## API Endpoints

### Public
- `POST /auth/login` - User login
- `GET /auth/logout` - User logout
- `GET /auth/status` - Check authentication
- `GET /health` - Health check

### Admin (Protected)
- `GET /admin/dashboard` - Admin dashboard
- `GET /admin/users` - User management
- `GET /admin/security` - Security dashboard

### User (Protected)
- `GET /user/dashboard` - User dashboard
- `GET /user/profile` - User profile

## Production Deployment

See [Installation Guide](./docs/INSTALLATION_GUIDE.md#production-deployment) for:
- PM2 Process Manager setup
- Nginx reverse proxy configuration
- SSL/TLS certificate setup
- Security hardening

## License

MIT

## Support

For issues or questions, please open an issue on GitHub.

---

**Made with ❤️ by haydigamal03-hash**

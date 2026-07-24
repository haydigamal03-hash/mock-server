import express from 'express';
import session from 'express-session';
import path from 'path';
import { fileURLToPath } from 'url';
import fs from 'fs';
import { initializeDatabase } from './config/database.js';
import { getEncryption } from './config/encryption.js';
import { securityHeaders, preventHiddenFileAccess, preventDirectoryTraversal, rateLimit, sanitizeInput, disableUnsafeMethods } from './middleware/security.js';
import { validateSession } from './middleware/route-protection.js';
import authRoutes from './routes/auth.js';
import adminProtectedRoutes from './routes/admin-protected.js';
import userProtectedRoutes from './routes/user-protected.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const PORT = process.env.PORT || 3000;
const NODE_ENV = process.env.NODE_ENV || 'development';
const HOST = 'localhost';

if (!fs.existsSync(path.join(__dirname, 'data'))) {
  fs.mkdirSync(path.join(__dirname, 'data'), { recursive: true });
}

app.use(disableUnsafeMethods);
app.use(securityHeaders);
app.use(preventHiddenFileAccess);
app.use(preventDirectoryTraversal);
app.use(express.json({ limit: '10kb' }));
app.use(express.urlencoded({ extended: true, limit: '10kb' }));
app.use(sanitizeInput);
app.use(rateLimit(100, 15 * 60 * 1000));

if (NODE_ENV === 'production') {
  app.set('trust proxy', 1);
}

const sessionSecret = process.env.SESSION_SECRET;
if (!sessionSecret) {
  console.error('ERROR: SESSION_SECRET environment variable is not set');
  process.exit(1);
}

app.use(session({
  secret: sessionSecret,
  resave: false,
  saveUninitialized: false,
  name: 'tron_session',
  cookie: {
    secure: NODE_ENV === 'production',
    httpOnly: true,
    sameSite: 'strict',
    maxAge: 24 * 60 * 60 * 1000,
    path: '/',
    domain: undefined
  }
}));

app.use(express.static(path.join(__dirname, 'public'), {
  maxAge: '1h',
  etag: false,
  dotfiles: 'deny'
}));

const startServer = async () => {
  try {
    console.log('\nInitializing MILD Security Framework\n');

    try {
      await getEncryption();
      console.log('Encryption module initialized (AES-256-GCM)');
    } catch (error) {
      console.error('Encryption initialization failed:', error.message);
      console.error('Make sure to run: npm run init');
      process.exit(1);
    }

    try {
      await initializeDatabase();
      console.log('Database initialized');
    } catch (error) {
      console.error('Database initialization failed:', error.message);
      process.exit(1);
    }

    console.log('\nSetting up routes\n');

    app.use('/auth', authRoutes);
    console.log('  Authentication routes mounted at /auth');

    app.use('/admin', validateSession, adminProtectedRoutes);
    console.log('  Admin routes mounted at /admin');

    app.use('/user', validateSession, userProtectedRoutes);
    console.log('  User routes mounted at /user');

    app.get('/health', (req, res) => {
      res.json({ status: 'ok', timestamp: new Date().toISOString() });
    });
    console.log('  Health check endpoint at /health');

    app.get('/', (req, res) => {
      if (req.session.userId) {
        return res.redirect(req.session.role === 'admin' ? '/admin' : '/user');
      }
      res.sendFile(path.join(__dirname, 'public/login.html'));
    });

    app.use((req, res) => {
      if (!req.session.userId && req.method === 'GET') {
        return res.redirect('/');
      }
      res.status(404).json({ error: 'Not found' });
    });

    app.use((err, req, res, next) => {
      console.error('[ERROR]', err);
      const message = NODE_ENV === 'production' ? 'Internal server error' : err.message;
      res.status(err.status || 500).json({ error: message });
    });

    app.listen(PORT, HOST, () => {
      console.log('\n' + '='.repeat(70));
      console.log('TRON Dashboard Server Started (MILD Security Enabled)');
      console.log('='.repeat(70));
      console.log(`\n  URL: http://${HOST}:${PORT}`);
      console.log(`  Environment: ${NODE_ENV}`);
      console.log(`  Security: MILD Framework - 7 Layers Active`);
      console.log('\n' + '='.repeat(70));
      console.log('\nDefault Credentials:');
      console.log('  Username: admin');
      console.log('  Password: admin123');
      console.log('\nChange these immediately after first login!\n');
    });
  } catch (error) {
    console.error('\nFailed to start server:', error);
    process.exit(1);
  }
};

process.on('SIGTERM', () => {
  console.log('\nSIGTERM received. Shutting down gracefully...');
  process.exit(0);
});

process.on('SIGINT', () => {
  console.log('\nSIGINT received. Shutting down gracefully...');
  process.exit(0);
});

startServer();
import { initializeEncryptionKey } from '../src/config/encryption.js';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

console.log('Initializing TRON Dashboard with MILD Security Framework\n');

try {
  const dataDir = path.join(__dirname, '../src/data');
  if (!fs.existsSync(dataDir)) {
    fs.mkdirSync(dataDir, { recursive: true });
    console.log('Data directory created');
  }

  initializeEncryptionKey();
  console.log('Encryption key initialized\n');

  console.log('Initialization complete!\n');
  console.log('Important Reminders:');
  console.log('  1. Set SESSION_SECRET environment variable');
  console.log('  2. Change default credentials (admin/admin123)');
  console.log('  3. Configure database connection');
  console.log('  4. Enable HTTPS in production\n');
} catch (error) {
  console.error('Initialization failed:', error.message);
  process.exit(1);
}
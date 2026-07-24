import crypto from 'crypto';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const encryptionKeyPath = path.join(__dirname, '../data/encryption.key');

let encryptionKey = null;

export const initializeEncryptionKey = () => {
  if (!fs.existsSync(encryptionKeyPath)) {
    const key = crypto.randomBytes(32);
    fs.writeFileSync(encryptionKeyPath, key);
    console.log('[ENCRYPTION] New encryption key generated');
  } else {
    encryptionKey = fs.readFileSync(encryptionKeyPath);
    console.log('[ENCRYPTION] Encryption key loaded');
  }
};

export const getEncryption = async () => {
  try {
    if (!encryptionKey) {
      if (!fs.existsSync(encryptionKeyPath)) {
        throw new Error('Encryption key not found. Run: npm run init');
      }
      encryptionKey = fs.readFileSync(encryptionKeyPath);
    }
    return {
      algorithm: 'aes-256-gcm',
      key: encryptionKey
    };
  } catch (error) {
    throw new Error('Encryption module initialization failed: ' + error.message);
  }
};

export const encrypt = (text, key) => {
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  let encrypted = cipher.update(text, 'utf8', 'hex');
  encrypted += cipher.final('hex');
  const authTag = cipher.getAuthTag();
  return iv.toString('hex') + ':' + authTag.toString('hex') + ':' + encrypted;
};

export const decrypt = (encryptedText, key) => {
  const parts = encryptedText.split(':');
  const iv = Buffer.from(parts[0], 'hex');
  const authTag = Buffer.from(parts[1], 'hex');
  const encrypted = parts[2];
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
  decipher.setAuthTag(authTag);
  let decrypted = decipher.update(encrypted, 'hex', 'utf8');
  decrypted += decipher.final('utf8');
  return decrypted;
};
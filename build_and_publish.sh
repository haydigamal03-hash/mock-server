#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO_NAME="${1:-b2b-web3-rpc-service}"
VISIBILITY="${2:-private}"   # private or public
GITHUB_ORG="${3:-}"          # optional organization

echo "Creating project scaffold in $ROOT"

# Create .gitignore
cat > .gitignore <<'GITIGNORE'
node_modules
dist
.env
.env.local
.DS_Store
coverage
.vscode
GITIGNORE

# .env.example
cat > .env.example <<'ENVEX'
PORT=3000
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/b2b_web3
REDIS_URL=redis://localhost:6379
JWT_ACCESS_SECRET=change_this_access_secret
JWT_REFRESH_SECRET=change_this_refresh_secret

# EVM RPC URLs
ALCHEMY_ETHEREUM_URL=https://alchemy.example
INFURA_ETHEREUM_URL=https://infura.example

# TRON RPC
TRONGRID_URL=https://api.trongrid.io
TRONGRID_API_KEY=YOUR_TRONGRID_API_KEY
ENVEX

# package.json (backend)
cat > package.json <<'PKG'
{
  "name": "b2b-web3-rpc-service",
  "version": "1.0.0",
  "main": "dist/server.js",
  "scripts": {
    "dev": "ts-node-dev --respawn --transpile-only src/server.ts",
    "build": "tsc",
    "start": "node dist/server.js",
    "prisma:generate": "prisma generate",
    "prisma:migrate": "prisma migrate deploy"
  },
  "dependencies": {
    "bcrypt": "^5.1.0",
    "dotenv": "^16.0.0",
    "ethers": "^6.0.0",
    "express": "^4.18.2",
    "jsonwebtoken": "^9.0.0",
    "prisma": "^5.0.0",
    "@prisma/client": "^5.0.0",
    "tronweb": "^4.0.0",
    "ioredis": "^5.0.0",
    "pino": "^8.0.0"
  },
  "devDependencies": {
    "ts-node-dev": "^2.0.0",
    "typescript": "^5.0.0",
    "@types/express": "^4.17.17",
    "@types/node": "^20.0.0"
  }
}
PKG

# tsconfig.json
cat > tsconfig.json <<'TSC'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "CommonJS",
    "outDir": "dist",
    "rootDir": "src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "resolveJsonModule": true,
    "typeRoots": ["./node_modules/@types", "./src/types"]
  },
  "include": ["src/**/*"]
}
TSC

# prisma/schema.prisma
mkdir -p prisma
cat > prisma/schema.prisma <<'PRISMA'
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model User {
  id         String   @id @default(uuid())
  email      String   @unique
  password   String
  name       String?
  role       Role     @default(USER)
  createdAt  DateTime @default(now())
  updatedAt  DateTime @updatedAt
  isActive   Boolean  @default(true)
}

model RpcProvider {
  id         String   @id @default(uuid())
  name       String
  chain      String
  url        String
  apiKey     String?
  priority   Int      @default(0)
  enabled    Boolean  @default(true)
  createdAt  DateTime @default(now())
  updatedAt  DateTime @updatedAt
}

enum Role {
  ADMIN
  MANAGER
  USER
}
PRISMA

# Dockerfile.backend
cat > Dockerfile.backend <<'DOCKB'
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --production
COPY . .
RUN npm run build
EXPOSE 3000
CMD ["node", "dist/server.js"]
DOCKB

# Dockerfile.frontend (minimal)
mkdir -p frontend-admin
cat > frontend-admin/Dockerfile.frontend <<'DOCKF'
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
CMD ["npm", "run", "dev"]
DOCKF

# docker-compose.yml
cat > docker-compose.yml <<'DC'
version: '3.8'
services:
  postgres:
    image: postgres:15
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: b2b_web3
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data

  redis:
    image: redis:7
    ports:
      - "6379:6379"

  backend:
    build:
      context: .
      dockerfile: Dockerfile.backend
    env_file:
      - .env
    ports:
      - "3000:3000"
    depends_on:
      - postgres
      - redis

  frontend:
    build:
      context: ./frontend-admin
      dockerfile: Dockerfile.frontend
    ports:
      - "5173:5173"
    depends_on:
      - backend

volumes:
  pgdata:
DC

# setup.sh
cat > setup.sh <<'SETUP'
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ ! -f "$ROOT_DIR/.env" ]; then
  cp "$ROOT_DIR/.env.example" "$ROOT_DIR/.env"
fi

docker-compose up -d postgres redis

echo "Waiting for Postgres..."
until docker exec $(docker-compose ps -q postgres) pg_isready -U postgres >/dev/null 2>&1; do
  sleep 1
done

npm ci
npx prisma generate || true
npx prisma migrate deploy || true

cd frontend-admin
npm ci
npm run build || npm run dev --if-present
cd "$ROOT_DIR"

docker-compose up -d --build backend frontend

node -e "
const { PrismaClient } = require('@prisma/client');
const bcrypt = require('bcrypt');
(async () => {
  const prisma = new PrismaClient();
  const email = 'admin@example.com';
  const existing = await prisma.user.findUnique({ where: { email } });
  if (!existing) {
    const hashed = await bcrypt.hash('Admin123!', 12);
    await prisma.user.create({ data: { email, password: hashed, name: 'Admin', role: 'ADMIN' } });
    console.log('Seeded admin user: admin@example.com / Admin123!');
  } else {
    console.log('Admin user already exists');
  }
  await prisma.$disconnect();
})();
"

echo "Setup complete."
SETUP
chmod +x setup.sh

# create_repo.sh
cat > create_repo.sh <<'CREATEREPO'
#!/usr/bin/env bash
set -euo pipefail
REPO_NAME="${1:-b2b-web3-rpc-service}"
VISIBILITY="${2:-private}"
GITHUB_ORG="${3:-}"

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI not found. Install and authenticate first."
  exit 1
fi

if [ ! -d .git ]; then
  git init
  git add .
  git commit -m "Initial commit"
fi

if [ -n "$GITHUB_ORG" ]; then
  gh repo create "$GITHUB_ORG/$REPO_NAME" --"$VISIBILITY" --description "Enterprise Web3 RPC Service with Admin" --confirm
  REMOTE="git@github.com:$GITHUB_ORG/$REPO_NAME.git"
else
  gh repo create "$REPO_NAME" --"$VISIBILITY" --description "Enterprise Web3 RPC Service with Admin" --confirm
  REMOTE="git@github.com:$(gh api user --jq .login)/$REPO_NAME.git"
fi

git remote add origin "$REMOTE" 2>/dev/null || git remote set-url origin "$REMOTE"
git branch -M main
git add .
git commit -m "Prepare repo for GitHub and ZIP" || true
git push -u origin main --force

echo "Repository created and pushed: $REMOTE"
CREATEREPO
chmod +x create_repo.sh

# GitHub Actions CI
mkdir -p .github/workflows
cat > .github/workflows/ci.yml <<'CIY'
name: CI

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  build:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: b2b_web3
        ports:
          - 5432:5432
        options: >-
          --health-cmd "pg_isready -U postgres" --health-interval 10s --health-timeout 5s --health-retries 5
      redis:
        image: redis:7
        ports:
          - 6379:6379

    steps:
      - uses: actions/checkout@v4
      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: 18
      - name: Install backend deps
        run: npm ci
      - name: Generate Prisma client
        env:
          DATABASE_URL: postgresql://postgres:postgres@localhost:5432/b2b_web3
        run: npx prisma generate
      - name: Build backend
        run: npm run build
      - name: Lint
        run: echo "Add lint step if configured"
CIY

# Create src files
mkdir -p src/config src/modules/web3 src/modules/auth src/modules/admin src/modules/users src/middlewares src/utils src/types

# src/app.ts
cat > src/app.ts <<'APP'
import express from 'express';
import authRoutes from './modules/auth/auth.routes';
import adminRoutes from './modules/admin/admin.routes';
import userRoutes from './modules/users/user.routes';
import rpcProviderRoutes from './modules/web3/rpcProvider.routes';
import { json } from 'express';

const app = express();
app.use(json());

app.get('/healthz', (_req, res) => res.json({ status: 'ok' }));

app.use('/api/v1/auth', authRoutes);
app.use('/api/v1/admin', adminRoutes);
app.use('/api/v1/users', userRoutes);
app.use('/api/v1/rpc-providers', rpcProviderRoutes);

export default app;
APP

# src/server.ts
cat > src/server.ts <<'SERVER'
import dotenv from 'dotenv';
dotenv.config();
import app from './app';
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`🚀 Server running on port ${PORT}`);
});
SERVER

# src/config/blockchain.ts
cat > src/config/blockchain.ts <<'BC'
import dotenv from 'dotenv';
dotenv.config();

export const BLOCKCHAIN_CONFIG = {
  evm: {
    providers: [
      process.env.ALCHEMY_ETHEREUM_URL || '',
      process.env.INFURA_ETHEREUM_URL || ''
    ].filter(Boolean)
  },
  tron: {
    url: process.env.TRONGRID_URL || 'https://api.trongrid.io',
    apiKey: process.env.TRONGRID_API_KEY || ''
  }
};
BC

# src/modules/web3/evmProvider.ts
cat > src/modules/web3/evmProvider.ts <<'EVMP'
import { JsonRpcProvider } from 'ethers';
import Redis from 'ioredis';
import { rpcProviderService } from './rpcProvider.service';

const redis = new Redis(process.env.REDIS_URL || 'redis://localhost:6379');

class EvmProviderService {
  private async getProvidersFromDb(): Promise<string[]> {
    const rows = await rpcProviderService.list('evm');
    return rows.filter(r => r.enabled).sort((a,b)=>a.priority-b.priority).map(r=>r.url);
  }

  async executeWithFailover<T>(rpcCall: (provider: JsonRpcProvider) => Promise<T>): Promise<T> {
    const cacheKey = 'evm:providers';
    let providers: string[] | null = JSON.parse(await redis.get(cacheKey) || 'null');
    if (!providers) {
      providers = await this.getProvidersFromDb();
      await redis.set(cacheKey, JSON.stringify(providers), 'EX', 60);
    }

    let lastError: any;
    for (const rpcUrl of providers) {
      try {
        const provider = new JsonRpcProvider(rpcUrl);
        return await rpcCall(provider);
      } catch (error) {
        console.warn(`[EVM RPC Warning] Failed to connect to ${rpcUrl}. Trying next provider...`);
        lastError = error;
      }
    }
    throw new Error(`[EVM RPC Error] All providers failed. Last error: ${lastError?.message}`);
  }

  async getEthBalance(address: string): Promise<string> {
    const cacheKey = `eth:balance:${address}`;
    const cached = await redis.get(cacheKey);
    if (cached) return cached;
    const balance = await this.executeWithFailover(async (provider) => {
      const b = await provider.getBalance(address);
      return b.toString();
    });
    await redis.set(cacheKey, balance, 'EX', 30);
    return balance;
  }
}

export const evmProviderService = new EvmProviderService();
EVMP

# src/modules/web3/tronProvider.ts
cat > src/modules/web3/tronProvider.ts <<'TRONP'
/* eslint-disable @typescript-eslint/no-var-requires */
// @ts-ignore
import TronWeb from 'tronweb';
import { BLOCKCHAIN_CONFIG } from '../../config/blockchain';

class TronProviderService {
  private tronWeb: any;

  constructor() {
    this.tronWeb = new TronWeb({
      fullHost: BLOCKCHAIN_CONFIG.tron.url,
      headers: { "TRON-PRO-API-KEY": BLOCKCHAIN_CONFIG.tron.apiKey }
    });
  }

  async getTrxBalance(address: string): Promise<number> {
    try {
      const balance = await this.tronWeb.trx.getBalance(address);
      return balance;
    } catch (error: any) {
      throw new Error(`[TRON RPC Error] ${error.message}`);
    }
  }
}

export const tronProviderService = new TronProviderService();
TRONP

# src/modules/web3/rpcProvider.model.ts
cat > src/modules/web3/rpcProvider.model.ts <<'MODEL'
import { PrismaClient } from '@prisma/client';
export const prisma = new PrismaClient();
MODEL

# src/modules/web3/rpcProvider.service.ts
cat > src/modules/web3/rpcProvider.service.ts <<'RPS'
import { prisma } from './rpcProvider.model';

export class RpcProviderService {
  async list(chain?: string) {
    return prisma.rpcProvider.findMany({
      where: chain ? { chain } : {},
      orderBy: { priority: 'asc' }
    });
  }

  async getById(id: string) {
    return prisma.rpcProvider.findUnique({ where: { id } });
  }

  async create(payload: {
    name: string;
    chain: string;
    url: string;
    apiKey?: string;
    priority?: number;
    enabled?: boolean;
  }) {
    return prisma.rpcProvider.create({ data: payload });
  }

  async update(id: string, data: Partial<{ name:string; url:string; apiKey:string; priority:number; enabled:boolean; chain:string }>) {
    return prisma.rpcProvider.update({ where: { id }, data });
  }

  async remove(id: string) {
    return prisma.rpcProvider.delete({ where: { id } });
  }
}

export const rpcProviderService = new RpcProviderService();
RPS

# src/modules/web3/rpcProvider.controller.ts
cat > src/modules/web3/rpcProvider.controller.ts <<'RPCCTRL'
import { Request, Response } from 'express';
import { rpcProviderService } from './rpcProvider.service';

export const RpcProviderController = {
  async list(req: Request, res: Response) {
    const chain = req.query.chain as string | undefined;
    const providers = await rpcProviderService.list(chain);
    res.json({ success: true, providers });
  },

  async get(req: Request, res: Response) {
    const { id } = req.params;
    const provider = await rpcProviderService.getById(id);
    if (!provider) return res.status(404).json({ success: false, error: 'Not found' });
    res.json({ success: true, provider });
  },

  async create(req: Request, res: Response) {
    const payload = req.body;
    const provider = await rpcProviderService.create(payload);
    res.json({ success: true, provider });
  },

  async update(req: Request, res: Response) {
    const { id } = req.params;
    const data = req.body;
    const provider = await rpcProviderService.update(id, data);
    res.json({ success: true, provider });
  },

  async remove(req: Request, res: Response) {
    const { id } = req.params;
    await rpcProviderService.remove(id);
    res.json({ success: true });
  }
};
RPCCTRL

# src/modules/web3/rpcProvider.routes.ts
cat > src/modules/web3/rpcProvider.routes.ts <<'RPCR'
import { Router } from 'express';
import { RpcProviderController } from './rpcProvider.controller';
import { authenticate, authorize } from '../../middlewares/auth.middleware';

const router = Router();

router.use(authenticate, authorize(['ADMIN']));

router.get('/', RpcProviderController.list);
router.get('/:id', RpcProviderController.get);
router.post('/', RpcProviderController.create);
router.put('/:id', RpcProviderController.update);
router.delete('/:id', RpcProviderController.remove);

export default router;
RPCR

# src/modules/auth/auth.service.ts
cat > src/modules/auth/auth.service.ts <<'AUTHS'
import bcrypt from 'bcrypt';
import { PrismaClient } from '@prisma/client';
import { signAccessToken, signRefreshToken } from '../../utils/jwt';

const prisma = new PrismaClient();

export class AuthService {
  async login(email: string, password: string) {
    const user = await prisma.user.findUnique({ where: { email } });
    if (!user) throw new Error('Invalid credentials');
    const ok = await bcrypt.compare(password, user.password);
    if (!ok) throw new Error('Invalid credentials');

    const accessToken = signAccessToken({ sub: user.id, role: user.role });
    const refreshToken = signRefreshToken({ sub: user.id });

    return { accessToken, refreshToken, user: { id: user.id, email: user.email, role: user.role } };
  }

  async register(payload: { email: string; password: string; name?: string; role?: string }) {
    const hashed = await bcrypt.hash(payload.password, 12);
    const user = await prisma.user.create({
      data: { email: payload.email, password: hashed, name: payload.name, role: payload.role as any }
    });
    return { id: user.id, email: user.email };
  }
}

export const authService = new AuthService();
AUTHS

# src/modules/auth/auth.controller.ts
cat > src/modules/auth/auth.controller.ts <<'AUTHC'
import { Request, Response } from 'express';
import { authService } from './auth.service';

export const AuthController = {
  async login(req: Request, res: Response) {
    try {
      const { email, password } = req.body;
      const data = await authService.login(email, password);
      res.json({ success: true, ...data });
    } catch (err: any) {
      res.status(401).json({ success: false, error: err.message });
    }
  },

  async register(req: Request, res: Response) {
    try {
      const data = await authService.register(req.body);
      res.json({ success: true, user: data });
    } catch (err: any) {
      res.status(400).json({ success: false, error: err.message });
    }
  }
};
AUTHC

# src/modules/auth/auth.routes.ts
cat > src/modules/auth/auth.routes.ts <<'AUTHR'
import { Router } from 'express';
import { AuthController } from './auth.controller';

const router = Router();
router.post('/login', AuthController.login);
router.post('/register', AuthController.register);

export default router;
AUTHR

# src/modules/admin/admin.controller.ts
cat > src/modules/admin/admin.controller.ts <<'ADMC'
import { Request, Response } from 'express';
import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient();

export const AdminController = {
  async listUsers(_req: Request, res: Response) {
    const users = await prisma.user.findMany();
    res.json({ success: true, users });
  },

  async createUser(req: Request, res: Response) {
    const { email, password, name, role } = req.body;
    const user = await prisma.user.create({ data: { email, password, name, role } });
    res.json({ success: true, user });
  },

  async updateUser(req: Request, res: Response) {
    const { id } = req.params;
    const data = req.body;
    const user = await prisma.user.update({ where: { id }, data });
    res.json({ success: true, user });
  },

  async deleteUser(req: Request, res: Response) {
    const { id } = req.params;
    await prisma.user.delete({ where: { id } });
    res.json({ success: true });
  }
};
ADMC

# src/modules/admin/admin.routes.ts
cat > src/modules/admin/admin.routes.ts <<'ADMRT'
import { Router } from 'express';
import { authenticate, authorize } from '../../middlewares/auth.middleware';
import { AdminController } from './admin.controller';

const router = Router();
router.use(authenticate, authorize(['ADMIN']));

router.get('/users', AdminController.listUsers);
router.post('/users', AdminController.createUser);
router.put('/users/:id', AdminController.updateUser);
router.delete('/users/:id', AdminController.deleteUser);

export default router;
ADMRT

# src/modules/users/user.routes.ts
cat > src/modules/users/user.routes.ts <<'USERR'
import { Router } from 'express';
import { authenticate } from '../../middlewares/auth.middleware';
import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient();
const router = Router();

router.get('/me', authenticate, async (req, res) => {
  const userId = (req as any).user.sub;
  const user = await prisma.user.findUnique({ where: { id: userId } });
  res.json({ success: true, user });
});

export default router;
USERR

# src/middlewares/auth.middleware.ts
cat > src/middlewares/auth.middleware.ts <<'AUTHM'
import { Request, Response, NextFunction } from 'express';
import { verifyAccessToken } from '../utils/jwt';

export function authenticate(req: Request, res: Response, next: NextFunction) {
  const auth = req.headers.authorization;
  if (!auth) return res.status(401).json({ error: 'Unauthorized' });
  const token = auth.split(' ')[1];
  try {
    const payload = verifyAccessToken(token) as any;
    (req as any).user = payload;
    next();
  } catch (err) {
    return res.status(401).json({ error: 'Invalid token' });
  }
}

export function authorize(roles: string[]) {
  return (req: Request, res: Response, next: NextFunction) => {
    const user = (req as any).user;
    if (!user || !roles.includes(user.role)) return res.status(403).json({ error: 'Forbidden' });
    next();
  };
}
AUTHM

# src/utils/jwt.ts
cat > src/utils/jwt.ts <<'JWTU'
import jwt from 'jsonwebtoken';
const ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'access-secret';
const REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'refresh-secret';

export function signAccessToken(payload: object) {
  return jwt.sign(payload, ACCESS_SECRET, { expiresIn: '15m' });
}
export function signRefreshToken(payload: object) {
  return jwt.sign(payload, REFRESH_SECRET, { expiresIn: '7d' });
}
export function verifyAccessToken(token: string) {
  return jwt.verify(token, ACCESS_SECRET);
}
JWTU

# src/types/index.d.ts (empty placeholder)
cat > src/types/index.d.ts <<'TYPES'
declare namespace Express {
  export interface Request {
    user?: any;
  }
}
TYPES

# Frontend scaffold files
mkdir -p frontend-admin/src/pages frontend-admin/src/components frontend-admin/src
# frontend package.json
cat > frontend-admin/package.json <<'FPG'
{
  "name": "frontend-admin",
  "version": "1.0.0",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "axios": "^1.4.0",
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "react-router-dom": "^6.14.0"
  },
  "devDependencies": {
    "typescript": "^5.0.0",
    "vite": "^5.0.0",
    "@types/react": "^18.0.0",
    "@types/react-dom": "^18.0.0",
    "tailwindcss": "^4.0.0",
    "postcss": "^8.0.0",
    "autoprefixer": "^10.0.0"
  }
}
FPG

# frontend tsconfig.json
cat > frontend-admin/tsconfig.json <<'FTSC'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "ESNext",
    "jsx": "react-jsx",
    "strict": true,
    "moduleResolution": "node",
    "esModuleInterop": true,
    "skipLibCheck": true
  },
  "include": ["src"]
}
FTSC

# vite.config.ts minimal
cat > frontend-admin/vite.config.ts <<'VITE'
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: { port: 5173 }
});
VITE

# tailwind.config.js minimal
cat > frontend-admin/tailwind.config.js <<'TW'
module.exports = {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: { extend: {} },
  plugins: []
};
TW

# frontend index.css
cat > frontend-admin/src/index.css <<'CSS'
@tailwind base;
@tailwind components;
@tailwind utilities;
CSS

# frontend main.tsx
cat > frontend-admin/src/main.tsx <<'MAIN'
import React from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter, Routes, Route } from 'react-router-dom';
import Login from './pages/Login';
import Dashboard from './pages/Dashboard';
import Users from './pages/Users';
import RpcProviders from './pages/RpcProviders';
import ProtectedRoute from './components/ProtectedRoute';
import './index.css';

createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <BrowserRouter>
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route path="/" element={<ProtectedRoute><Dashboard /></ProtectedRoute>} />
        <Route path="/users" element={<ProtectedRoute><Users /></ProtectedRoute>} />
        <Route path="/rpc-providers" element={<ProtectedRoute><RpcProviders /></ProtectedRoute>} />
      </Routes>
    </BrowserRouter>
  </React.StrictMode>
);
MAIN

# frontend App.tsx placeholder
cat > frontend-admin/src/App.tsx <<'APPX'
import React from 'react';
export default function App() {
  return <div>Admin App</div>;
}
APPX

# frontend pages
cat > frontend-admin/src/pages/Login.tsx <<'LOGIN'
import React, { useState } from 'react';
import axios from 'axios';
import { useNavigate } from 'react-router-dom';

export default function Login() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const nav = useNavigate();

  async function submit(e: any) {
    e.preventDefault();
    const res = await axios.post('/api/v1/auth/login', { email, password });
    localStorage.setItem('accessToken', res.data.accessToken);
    nav('/');
  }

  return (
    <div className="min-h-screen flex items-center justify-center">
      <form onSubmit={submit} className="w-full max-w-sm bg-white p-6 rounded shadow">
        <h2 className="text-xl font-bold mb-4">Admin Login</h2>
        <input value={email} onChange={e=>setEmail(e.target.value)} placeholder="Email" className="w-full mb-2 p-2 border" />
        <input type="password" value={password} onChange={e=>setPassword(e.target.value)} placeholder="Password" className="w-full mb-2 p-2 border" />
        <button className="mt-4 bg-blue-600 text-white px-4 py-2 rounded">Login</button>
      </form>
    </div>
  );
}
LOGIN

cat > frontend-admin/src/pages/Dashboard.tsx <<'DASH'
import React from 'react';
export default function Dashboard() {
  return <div className="p-6">Dashboard placeholder</div>;
}
DASH

cat > frontend-admin/src/pages/Users.tsx <<'USERS'
import React from 'react';
export default function Users() {
  return <div className="p-6">Users placeholder</div>;
}
USERS

# RpcProviders page
cat > frontend-admin/src/pages/RpcProviders.tsx <<'RPCPAGE'
import React, { useEffect, useState } from 'react';
import axios from 'axios';

type Provider = {
  id?: string;
  name: string;
  chain: string;
  url: string;
  apiKey?: string;
  priority?: number;
  enabled?: boolean;
};

export default function RpcProviders() {
  const [list, setList] = useState<Provider[]>([]);
  const [form, setForm] = useState<Provider>({ name:'', chain:'evm', url:'', priority:0, enabled:true });

  async function fetchList() {
    const res = await axios.get('/api/v1/rpc-providers');
    setList(res.data.providers || []);
  }

  useEffect(()=>{ fetchList(); }, []);

  async function save() {
    if (form.id) {
      await axios.put(`/api/v1/rpc-providers/${form.id}`, form);
    } else {
      await axios.post('/api/v1/rpc-providers', form);
    }
    setForm({ name:'', chain:'evm', url:'', priority:0, enabled:true });
    fetchList();
  }

  async function edit(p: Provider) { setForm(p); }
  async function remove(id?: string) { if(!id) return; await axios.delete(`/api/v1/rpc-providers/${id}`); fetchList(); }

  return (
    <div className="p-6">
      <h2 className="text-xl font-bold mb-4">RPC Providers</h2>
      <div className="mb-4 grid grid-cols-2 gap-4">
        <input placeholder="Name" value={form.name} onChange={e=>setForm({...form, name:e.target.value})} className="p-2 border" />
        <select value={form.chain} onChange={e=>setForm({...form, chain:e.target.value})} className="p-2 border">
          <option value="evm">EVM</option>
          <option value="tron">TRON</option>
        </select>
        <input placeholder="URL" value={form.url} onChange={e=>setForm({...form, url:e.target.value})} className="p-2 border col-span-2" />
        <input placeholder="API Key" value={form.apiKey||''} onChange={e=>setForm({...form, apiKey:e.target.value})} className="p-2 border" />
        <input type="number" placeholder="Priority" value={form.priority} onChange={e=>setForm({...form, priority:parseInt(e.target.value||'0')})} className="p-2 border" />
        <label className="flex items-center"><input type="checkbox" checked={form.enabled} onChange={e=>setForm({...form, enabled:e.target.checked})} /> Enabled</label>
        <button onClick={save} className="bg-green-600 text-white px-4 py-2 rounded">Save</button>
      </div>

      <table className="w-full table-auto">
        <thead><tr><th>Name</th><th>Chain</th><th>URL</th><th>Priority</th><th>Enabled</th><th>Actions</th></tr></thead>
        <tbody>
          {list.map(p=>(
            <tr key={p.id}>
              <td>{p.name}</td>
              <td>{p.chain}</td>
              <td className="truncate max-w-xs">{p.url}</td>
              <td>{p.priority}</td>
              <td>{p.enabled ? 'Yes' : 'No'}</td>
              <td>
                <button onClick={()=>edit(p)} className="mr-2 text-blue-600">Edit</button>
                <button onClick={()=>remove(p.id)} className="text-red-600">Delete</button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
RPCPAGE

# frontend ProtectedRoute
cat > frontend-admin/src/components/ProtectedRoute.tsx <<'PROT'
import React from 'react';
import { Navigate } from 'react-router-dom';

export default function ProtectedRoute({ children }: { children: JSX.Element }) {
  const token = localStorage.getItem('accessToken');
  if (!token) return <Navigate to="/login" replace />;
  return children;
}
PROT

# frontend Navbar placeholder
cat > frontend-admin/src/components/Navbar.tsx <<'NAV'
import React from 'react';
export default function Navbar() {
  return <nav className="p-4 bg-gray-100">Navbar</nav>;
}
NAV

# frontend index.html
cat > frontend-admin/index.html <<'HTML'
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Admin</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
HTML

# Create ZIP archive
ZIP_NAME="${REPO_NAME}.zip"
echo "Creating ZIP archive: $ZIP_NAME"
git init >/dev/null 2>&1 || true
git add . >/dev/null 2>&1 || true
git commit -m "scaffold" >/dev/null 2>&1 || true
git archive -o "$ZIP_NAME" HEAD || (zip -r "$ZIP_NAME" . -x .git\* node_modules\* dist\* "*.env" "*.env.local" .DS_Store)

# Create and push GitHub repo if gh available
if command -v gh >/dev/null 2>&1; then
  echo "Creating GitHub repo..."
  if [ -n "$GITHUB_ORG" ]; then
    gh repo create "$GITHUB_ORG/$REPO_NAME" --"$VISIBILITY" --description "Enterprise Web3 RPC Service with Admin" --confirm
    REMOTE="git@github.com:$GITHUB_ORG/$REPO_NAME.git"
  else
    gh repo create "$REPO_NAME" --"$VISIBILITY" --description "Enterprise Web3 RPC Service with Admin" --confirm
    REMOTE="git@github.com:$(gh api user --jq .login)/$REPO_NAME.git"
  fi
  git remote add origin "$REMOTE" 2>/dev/null || git remote set-url origin "$REMOTE"
  git branch -M main
  git push -u origin main --force
  echo "Pushed to $REMOTE"
else
  echo "gh CLI not found; skipping GitHub repo creation. ZIP created locally."
fi

echo "Done. ZIP: $(pwd)/$ZIP_NAME"

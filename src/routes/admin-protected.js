import express from 'express';
import { requireAdmin } from '../middleware/route-protection.js';

const router = express.Router();

router.use(requireAdmin);

router.get('/dashboard', (req, res) => {
  res.json({
    message: 'Admin Dashboard',
    user: req.session.username,
    role: req.session.role
  });
});

router.get('/users', (req, res) => {
  res.json({
    message: 'User Management',
    users: []
  });
});

router.get('/security', (req, res) => {
  res.json({
    message: 'Security Dashboard',
    framework: 'MILD Security Framework',
    layers: 7,
    status: 'Active'
  });
});

export default router;
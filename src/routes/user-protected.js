import express from 'express';
import { requireUser } from '../middleware/route-protection.js';

const router = express.Router();

router.use(requireUser);

router.get('/dashboard', (req, res) => {
  res.json({
    message: 'User Dashboard',
    user: req.session.username,
    role: req.session.role
  });
});

router.get('/profile', (req, res) => {
  res.json({
    userId: req.session.userId,
    username: req.session.username,
    role: req.session.role
  });
});

export default router;
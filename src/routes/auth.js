import express from 'express';

const router = express.Router();

router.post('/login', (req, res) => {
  const { username, password } = req.body;

  if (username === 'admin' && password === 'admin123') {
    req.session.userId = 1;
    req.session.role = 'admin';
    req.session.username = 'admin';
    return res.json({ success: true, message: 'Logged in successfully' });
  }

  if (username === 'user' && password === 'user123') {
    req.session.userId = 2;
    req.session.role = 'user';
    req.session.username = 'user';
    return res.json({ success: true, message: 'Logged in successfully' });
  }

  res.status(401).json({ error: 'Invalid credentials' });
});

router.get('/logout', (req, res) => {
  req.session.destroy((err) => {
    if (err) {
      return res.status(500).json({ error: 'Failed to logout' });
    }
    res.json({ success: true, message: 'Logged out successfully' });
  });
});

router.get('/status', (req, res) => {
  if (req.session.userId) {
    return res.json({
      authenticated: true,
      userId: req.session.userId,
      role: req.session.role,
      username: req.session.username
    });
  }
  res.json({ authenticated: false });
});

export default router;
export const validateSession = (req, res, next) => {
  if (!req.session || !req.session.userId) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  next();
};

export const requireAdmin = (req, res, next) => {
  if (!req.session || req.session.role !== 'admin') {
    return res.status(403).json({ error: 'Forbidden - Admin access required' });
  }
  next();
};

export const requireUser = (req, res, next) => {
  if (!req.session || (req.session.role !== 'user' && req.session.role !== 'admin')) {
    return res.status(403).json({ error: 'Forbidden - User access required' });
  }
  next();
};
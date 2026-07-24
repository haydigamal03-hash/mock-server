import crypto from 'crypto';

export const disableUnsafeMethods = (req, res, next) => {
  const unsafeMethods = ['TRACE', 'CONNECT'];
  if (unsafeMethods.includes(req.method)) {
    return res.status(405).json({ error: 'Method not allowed' });
  }
  next();
};

export const securityHeaders = (req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('X-XSS-Protection', '1; mode=block');
  res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
  res.setHeader('Content-Security-Policy', "default-src 'self'");
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
  res.setHeader('Permissions-Policy', 'geolocation=(), microphone=(), camera=()');
  next();
};

export const preventHiddenFileAccess = (req, res, next) => {
  if (req.path.includes('/.')  || req.path.startsWith('.')) {
    return res.status(403).json({ error: 'Access denied' });
  }
  next();
};

export const preventDirectoryTraversal = (req, res, next) => {
  const path = req.path;
  if (path.includes('..') || path.includes('\\')) {
    return res.status(403).json({ error: 'Invalid path' });
  }
  next();
};

export const sanitizeInput = (req, res, next) => {
  const sqlPatterns = [
    /(--|#|\*|\{|\})/gi,
    /('|(\-\-)|(;)|(\|\|)|(\*))/gi,
    /(union|select|insert|update|delete|drop|create|alter)/gi
  ];

  const xssPatterns = [
    /<script[^>]*>.*?<\/script>/gi,
    /javascript:/gi,
    /on\w+\s*=/gi,
    /<iframe/gi,
    /<object/gi,
    /<embed/gi
  ];

  const commandPatterns = [
    /[;&|`$(){}\[\]]/g
  ];

  const sanitizeValue = (value) => {
    if (typeof value !== 'string') return value;

    for (const pattern of sqlPatterns) {
      if (pattern.test(value)) {
        console.warn('[SECURITY] SQL Injection pattern detected:', value);
        throw new Error('Invalid input detected');
      }
    }

    for (const pattern of xssPatterns) {
      if (pattern.test(value)) {
        console.warn('[SECURITY] XSS pattern detected:', value);
        return value.replace(pattern, '');
      }
    }

    if (commandPatterns.test(value)) {
      console.warn('[SECURITY] Command injection pattern detected:', value);
      throw new Error('Invalid input detected');
    }

    return value;
  };

  if (req.body && typeof req.body === 'object') {
    for (const key in req.body) {
      try {
        req.body[key] = sanitizeValue(req.body[key]);
      } catch (error) {
        return res.status(400).json({ error: error.message });
      }
    }
  }

  if (req.query && typeof req.query === 'object') {
    for (const key in req.query) {
      try {
        req.query[key] = sanitizeValue(req.query[key]);
      } catch (error) {
        return res.status(400).json({ error: error.message });
      }
    }
  }

  next();
};

const ipRequestMap = new Map();

export const rateLimit = (maxRequests, windowMs) => {
  return (req, res, next) => {
    const ip = req.ip || req.connection.remoteAddress;
    const now = Date.now();
    const userRequests = ipRequestMap.get(ip) || [];
    
    const validRequests = userRequests.filter(time => now - time < windowMs);
    
    if (validRequests.length >= maxRequests) {
      console.warn(`[SECURITY] Rate limit exceeded for IP: ${ip}`);
      return res.status(429).json({ error: 'Too many requests' });
    }
    
    validRequests.push(now);
    ipRequestMap.set(ip, validRequests);
    
    next();
  };
};

export const sanitizeErrorMessage = (error, env = 'development') => {
  if (env === 'production') {
    return 'Internal server error';
  }
  return error.message;
};
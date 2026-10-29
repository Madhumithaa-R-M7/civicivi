const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const db = require('../db');

// Role hierarchy levels
const ROLE_HIERARCHY = {
  user: 1,
  staff: 2,
  admin: 3,
  super_admin: 4,
};

/**
 * Hash raw JWT for safe database storage and revocation lookups
 */
function hashToken(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

/**
 * Primary Authentication Middleware
 * Validates JWT signature, expiration, and checks against revoked sessions in PostgreSQL.
 */
const authenticateToken = async (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1]; // Bearer <token>

  if (!token) {
    return res.status(401).json({ success: false, message: 'Access denied: No token provided' });
  }

  try {
    const verified = jwt.verify(token, process.env.JWT_SECRET || 'civicconnect_super_secret_jwt_key_2026');
    
    // Check session revocation in PostgreSQL if session tracking is active
    try {
      const tokenH = hashToken(token);
      const session = await db.query(
        'SELECT is_revoked FROM auth_sessions WHERE token_hash = $1',
        [tokenH]
      );
      if (session.rows.length > 0 && session.rows[0].is_revoked) {
        return res.status(401).json({ success: false, message: 'Session has been revoked. Please sign in again.' });
      }
    } catch (_) {
      // Non-blocking if table is temporarily unreachable
    }

    req.user = verified;
    req.rawToken = token;
    next();
  } catch (err) {
    return res.status(403).json({ success: false, message: 'Invalid or expired token' });
  }
};

/**
 * Optional Authentication Middleware
 * Populates req.user if valid token provided; does not reject unauthenticated calls.
 */
const optionalAuth = async (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) {
    req.user = null;
    return next();
  }

  try {
    const verified = jwt.verify(token, process.env.JWT_SECRET || 'civicconnect_super_secret_jwt_key_2026');
    req.user = verified;
    req.rawToken = token;
  } catch (err) {
    req.user = null;
  }
  next();
};

/**
 * Role-Based Access Control Middleware (Whitelisted Roles)
 */
const requireRoles = (allowedRoles = []) => {
  return (req, res, next) => {
    if (!req.user) {
      return res.status(401).json({ success: false, message: 'Authentication required' });
    }

    const userRole = req.user.role || 'user';
    if (!allowedRoles.includes(userRole)) {
      return res.status(403).json({
        success: false,
        message: `Forbidden: Access restricted to authorized personnel (${allowedRoles.join(', ')})`,
      });
    }
    next();
  };
};

/**
 * Minimum Role Hierarchy Middleware
 */
const requireMinRole = (minRole) => {
  return (req, res, next) => {
    if (!req.user) {
      return res.status(401).json({ success: false, message: 'Authentication required' });
    }

    const userRole = req.user.role || 'user';
    const userLevel = ROLE_HIERARCHY[userRole] || 1;
    const requiredLevel = ROLE_HIERARCHY[minRole] || 1;

    if (userLevel < requiredLevel) {
      return res.status(403).json({
        success: false,
        message: `Forbidden: Requires at least ${minRole} privilege level`,
      });
    }
    next();
  };
};

// Common RBAC shortcuts
const requireStaffOrAdmin = requireRoles(['staff', 'admin', 'super_admin']);
const requireAdmin = requireRoles(['admin', 'super_admin']);
const requireSuperAdmin = requireRoles(['super_admin']);

module.exports = {
  authenticateToken,
  optionalAuth,
  requireRoles,
  requireMinRole,
  requireStaffOrAdmin,
  requireAdmin,
  requireSuperAdmin,
  hashToken,
  ROLE_HIERARCHY,
};

const express = require('express');
const router = express.Router();
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const db = require('../db');
const rateLimit = require('express-rate-limit');
const { authenticateToken, hashToken } = require('../middleware/auth');
const { sendSms } = require('../services/sms');
const { sendPasswordResetEmail } = require('../services/email');

// API rate-limiter for authentication endpoints
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: process.env.NODE_ENV === 'test' ? 1000 : 30, // 30 attempts per 15 min (or 1000 in test)
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, message: 'Too many authentication attempts. Please try again after 15 minutes.' },
});

// Helper to sanitize and normalize phone numbers (e.g., E.164 format +91XXXXXXXXXX)
function normalizePhone(phone) {
  if (!phone) return '';
  let clean = phone.trim().replace(/[^\d+]/g, '');
  // Strip leading 0 if 11 digits (e.g., 09876543210 -> 9876543210)
  if (clean.startsWith('0') && clean.length === 11) {
    clean = clean.substring(1);
  }
  if (!clean.startsWith('+')) {
    if (clean.length === 10) clean = '+91' + clean;
    else if (clean.length === 12 && clean.startsWith('91')) clean = '+' + clean;
    else clean = '+' + clean;
  }
  return clean;
}

// Helper to validate email format
function isValidEmail(email) {
  if (!email) return false;
  const re = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return re.test(email.trim().toLowerCase());
}

/**
 * @route   POST /api/auth/register
 * @desc    Register a new citizen user (Email/Password or Phone)
 */
router.post('/register', authLimiter, async (req, res) => {
  try {
    const { name, email, phone, password } = req.body;
    // Public self-registration always assigns 'user' role for security
    const assignedRole = 'user';

    if (!name || name.trim().length === 0) {
      return res.status(400).json({
        success: false,
        message: 'Full name is required.',
      });
    }

    if (!email && !phone) {
      return res.status(400).json({
        success: false,
        message: 'Either email or mobile number is required.',
      });
    }

    let cleanEmail = null;
    if (email && email.trim().length > 0) {
      cleanEmail = email.trim().toLowerCase();
      if (!isValidEmail(cleanEmail)) {
        return res.status(400).json({
          success: false,
          message: 'Please provide a valid email address.',
        });
      }
    }

    let cleanPhone = null;
    if (phone && phone.trim().length > 0) {
      cleanPhone = normalizePhone(phone);
      if (cleanPhone.length < 11) {
        return res.status(400).json({
          success: false,
          message: 'Please provide a valid 10-digit mobile number.',
        });
      }
    }

    // Check for existing user with same email or phone
    const existing = await db.query(
      `SELECT id, email, phone FROM users 
       WHERE (email IS NOT NULL AND email = $1) 
          OR (phone IS NOT NULL AND phone = $2)`,
      [cleanEmail, cleanPhone]
    );

    if (existing.rows.length > 0) {
      const match = existing.rows[0];
      if (cleanEmail && match.email === cleanEmail) {
        return res.status(409).json({ success: false, message: 'An account with this email already exists.' });
      }
      if (cleanPhone && match.phone === cleanPhone) {
        return res.status(409).json({ success: false, message: 'An account with this phone number already exists.' });
      }
    }

    let passwordHash = null;
    if (password && password.trim().length > 0) {
      if (password.length < 6) {
        return res.status(400).json({ success: false, message: 'Password must be at least 6 characters long.' });
      }
      passwordHash = await bcrypt.hash(password, 10);
    }

    const result = await db.query(
      `INSERT INTO users (name, email, phone, password_hash, role, location, points, is_verified)
       VALUES ($1, $2, $3, $4, $5, 'Mumbai', 0, FALSE)
       RETURNING id, name, email, phone, role, location, points, is_verified, created_at`,
      [name.trim(), cleanEmail, cleanPhone, passwordHash, assignedRole]
    );

    const user = result.rows[0];
    const token = jwt.sign(
      { id: user.id, role: user.role, name: user.name, jti: crypto.randomBytes(16).toString('hex') },
      process.env.JWT_SECRET || 'civicconnect_super_secret_jwt_key_2026',
      { expiresIn: '30d' }
    );

    // Record session in auth_sessions
    try {
      const tokenH = hashToken(token);
      const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
      await db.query(
        `INSERT INTO auth_sessions (user_id, token_hash, ip_address, user_agent, expires_at)
         VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (token_hash) DO NOTHING`,
        [user.id, tokenH, req.ip || req.connection?.remoteAddress, req.headers['user-agent'] || null, expiresAt]
      );
    } catch (sessionErr) {
      console.warn('[AUTH] Could not record auth_session:', sessionErr.message);
    }

    // Record registration in audit_logs
    try {
      await db.query(
        `INSERT INTO audit_logs (actor_id, action, entity_type, entity_id, new_values, ip_address)
         VALUES ($1, 'USER_REGISTERED', 'users', $2, $3, $4)`,
        [
          user.id,
          user.id,
          JSON.stringify({ email: user.email, phone: user.phone, role: user.role }),
          req.ip || req.connection?.remoteAddress,
        ]
      );
    } catch (auditErr) {
      console.warn('[AUTH] Could not record registration audit log:', auditErr.message);
    }

    res.status(201).json({
      success: true,
      message: 'Registration successful',
      token,
      user,
    });
  } catch (err) {
    console.error('Error during registration:', err.message);
    res.status(500).json({ success: false, message: 'Server error during registration' });
  }
});

/**
 * @route   POST /api/auth/login
 * @desc    Login with email/phone and password
 *          Returns generic error messages to prevent account enumeration.
 */
router.post('/login', authLimiter, async (req, res) => {
  try {
    const { identifier, password } = req.body;

    if (!identifier || !password) {
      return res.status(400).json({
        success: false,
        message: 'Please provide both email/phone and password.',
      });
    }

    const cleanId = identifier.trim().toLowerCase();
    const cleanPhone = normalizePhone(identifier);

    // Parameterized lookup for user
    const result = await db.query(
      `SELECT * FROM users WHERE LOWER(email) = $1 OR phone = $2 OR phone = $1`,
      [cleanId, cleanPhone]
    );

    // Generic error message to prevent user enumeration
    const genericAuthError = {
      success: false,
      message: 'Invalid email or password.',
    };

    if (result.rows.length === 0) {
      return res.status(401).json(genericAuthError);
    }

    const user = result.rows[0];

    // If account has no password set (e.g. registered via OTP only)
    if (!user.password_hash) {
      return res.status(401).json(genericAuthError);
    }

    // Verify password hash
    const match = await bcrypt.compare(password, user.password_hash);
    if (!match) {
      return res.status(401).json(genericAuthError);
    }

    const token = jwt.sign(
      { id: user.id, role: user.role, name: user.name, jti: crypto.randomBytes(16).toString('hex') },
      process.env.JWT_SECRET || 'civicconnect_super_secret_jwt_key_2026',
      { expiresIn: '30d' }
    );

    // Record session in auth_sessions
    try {
      const tokenH = hashToken(token);
      const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
      await db.query(
        `INSERT INTO auth_sessions (user_id, token_hash, ip_address, user_agent, expires_at)
         VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (token_hash) DO NOTHING`,
        [user.id, tokenH, req.ip || req.connection?.remoteAddress, req.headers['user-agent'] || null, expiresAt]
      );
    } catch (sessionErr) {
      console.warn('[AUTH] Could not record auth_session on login:', sessionErr.message);
    }

    // Record login in audit_logs
    try {
      await db.query(
        `INSERT INTO audit_logs (actor_id, action, entity_type, entity_id, new_values, ip_address)
         VALUES ($1, 'USER_LOGIN', 'users', $2, $3, $4)`,
        [
          user.id,
          user.id,
          JSON.stringify({ identifier: cleanId || cleanPhone }),
          req.ip || req.connection?.remoteAddress,
        ]
      );
    } catch (auditErr) {
      console.warn('[AUTH] Could not record login audit log:', auditErr.message);
    }

    // Clean user object before responding
    delete user.password_hash;

    res.json({
      success: true,
      message: 'Login successful',
      token,
      user,
    });
  } catch (err) {
    console.error('Error during login:', err.message);
    res.status(500).json({ success: false, message: 'Server error during login' });
  }
});

/**
 * @route   POST /api/auth/send-otp
 * @desc    Generate cryptographically secure 6-digit OTP, store bcrypt hash in PostgreSQL,
 *          and send via configured SMS provider.
 */
router.post('/send-otp', async (req, res) => {
  try {
    const { phone } = req.body;

    if (!phone) {
      return res.status(400).json({ success: false, message: 'Phone number is required.' });
    }

    const cleanPhone = normalizePhone(phone);
    if (cleanPhone.length < 11) {
      return res.status(400).json({ success: false, message: 'Please provide a valid 10-digit mobile number.' });
    }

    // Rate-limiting / Cooldown check:
    // Look for any OTP requested for this phone within the last 60 seconds for phone_auth
    const recentChallenge = await db.query(
      `SELECT created_at FROM otp_challenges 
       WHERE phone = $1 AND purpose = 'phone_auth' AND created_at > (CURRENT_TIMESTAMP - INTERVAL '60 seconds')
       ORDER BY created_at DESC LIMIT 1`,
      [cleanPhone]
    );

    if (recentChallenge.rows.length > 0) {
      const elapsedMs = Date.now() - new Date(recentChallenge.rows[0].created_at).getTime();
      const waitSecs = Math.max(1, Math.ceil((60000 - elapsedMs) / 1000));
      return res.status(429).json({
        success: false,
        message: `Please wait ${waitSecs} seconds before requesting a new OTP.`,
        cooldownSeconds: waitSecs,
      });
    }

    // Invalidate previous unconsumed challenges for this phone with purpose 'phone_auth'
    await db.query(
      `UPDATE otp_challenges 
       SET is_consumed = TRUE 
       WHERE phone = $1 AND purpose = 'phone_auth' AND is_consumed = FALSE`,
      [cleanPhone]
    );

    // Generate cryptographically secure random 6-digit OTP
    const otpInt = crypto.randomInt(100000, 1000000);
    const otp = otpInt.toString();

    // Unique challenge verification ID
    const verificationId = 'vid_' + crypto.randomBytes(16).toString('hex');

    // Hash the OTP with bcrypt (10 rounds) before storing in PostgreSQL
    const otpHash = await bcrypt.hash(otp, 10);

    // 5 minutes expiry
    const expiresAt = new Date(Date.now() + 5 * 60 * 1000);

    // Store hashed OTP in PostgreSQL with distinct purpose 'phone_auth'
    await db.query(
      `INSERT INTO otp_challenges (verification_id, phone, otp_hash, purpose, attempts, max_attempts, is_consumed, expires_at)
       VALUES ($1, $2, $3, 'phone_auth', 0, 5, FALSE, $4)`,
      [verificationId, cleanPhone, otpHash, expiresAt]
    );

    // Dispatch SMS via configured provider (Twilio, Fast2SMS, or mock in dev)
    let smsResult;
    try {
      smsResult = await sendSms(cleanPhone, otp);
    } catch (smsErr) {
      console.error(`[AUTH-SEND-OTP] ❌ Failed to dispatch SMS via provider:`, smsErr.message);
      // Clean up the challenge in PostgreSQL so a failed dispatch challenge doesn't lock out the user
      await db.query(
        `UPDATE otp_challenges SET is_consumed = TRUE WHERE verification_id = $1`,
        [verificationId]
      );
      return res.status(502).json({
        success: false,
        message: `SMS provider error: ${smsErr.message}`,
        provider: process.env.SMS_PROVIDER || 'unconfigured',
      });
    }

    res.json({
      success: true,
      message: `OTP sent successfully to ${cleanPhone}`,
      verificationId,
      expiresIn: 300,
      provider: smsResult.provider,
      // Provide devOtp only in development mode when mock provider was explicitly enabled
      devOtp: process.env.NODE_ENV === 'production' ? undefined : smsResult.devOtp,
    });
  } catch (err) {
    console.error('Error sending OTP:', err.message);
    res.status(500).json({ success: false, message: 'Failed to send OTP' });
  }
});

/**
 * @route   POST /api/auth/verify-otp
 * @desc    Verify OTP code against bcrypt hash stored in PostgreSQL,
 *          enforce attempt limits, expiration, and single-use consumption.
 */
router.post('/verify-otp', async (req, res) => {
  try {
    const { verificationId, phone, otp, name } = req.body;

    if ((!verificationId && !phone) || !otp) {
      return res.status(400).json({
        success: false,
        message: 'Verification ID (or phone) and OTP code are required.',
      });
    }

    // Retrieve active challenge from PostgreSQL specifically with purpose 'phone_auth'
    let challengeRes;
    if (verificationId) {
      challengeRes = await db.query(
        `SELECT * FROM otp_challenges WHERE verification_id = $1 AND purpose = 'phone_auth'`,
        [verificationId]
      );
    } else {
      const cleanPhone = normalizePhone(phone);
      challengeRes = await db.query(
        `SELECT * FROM otp_challenges WHERE phone = $1 AND purpose = 'phone_auth' ORDER BY created_at DESC LIMIT 1`,
        [cleanPhone]
      );
    }

    if (challengeRes.rows.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'Invalid or expired OTP session. Please request a new code.',
      });
    }

    const challenge = challengeRes.rows[0];

    // Check if OTP was already consumed (replay attack prevention)
    if (challenge.is_consumed) {
      return res.status(400).json({
        success: false,
        message: 'This OTP has already been used. Please request a new code.',
      });
    }

    // Check expiration (5 minutes limit)
    if (new Date() > new Date(challenge.expires_at)) {
      await db.query(`UPDATE otp_challenges SET is_consumed = TRUE WHERE id = $1`, [challenge.id]);
      return res.status(400).json({
        success: false,
        message: 'OTP has expired. Please request a new code.',
      });
    }

    // Check attempt limits (max 5)
    if (challenge.attempts >= challenge.max_attempts) {
      await db.query(`UPDATE otp_challenges SET is_consumed = TRUE WHERE id = $1`, [challenge.id]);
      return res.status(429).json({
        success: false,
        message: 'Too many incorrect attempts. Please request a new OTP.',
      });
    }

    // Verify submitted OTP against bcrypt hash stored in PostgreSQL
    const isMatch = await bcrypt.compare(otp.trim(), challenge.otp_hash);

    if (!isMatch) {
      const newAttempts = challenge.attempts + 1;
      const remainingAttempts = Math.max(0, challenge.max_attempts - newAttempts);

      if (remainingAttempts === 0) {
        await db.query(
          `UPDATE otp_challenges SET attempts = $1, is_consumed = TRUE WHERE id = $2`,
          [newAttempts, challenge.id]
        );
        return res.status(429).json({
          success: false,
          message: 'Too many incorrect attempts. This OTP session has been locked. Please request a new one.',
        });
      } else {
        await db.query(
          `UPDATE otp_challenges SET attempts = $1 WHERE id = $2`,
          [newAttempts, challenge.id]
        );
        return res.status(400).json({
          success: false,
          message: `Invalid OTP code. (${remainingAttempts} attempts remaining)`,
          remainingAttempts,
        });
      }
    }

    // Valid OTP! Invalidate challenge immediately to prevent reuse
    await db.query(`UPDATE otp_challenges SET is_consumed = TRUE WHERE id = $1`, [challenge.id]);

    const verifiedPhone = challenge.phone;

    // Find or create citizen user in PostgreSQL
    let userQuery = await db.query('SELECT * FROM users WHERE phone = $1', [verifiedPhone]);
    let user;

    if (userQuery.rows.length === 0) {
      const displayName = name && name.trim().length > 0 ? name.trim() : `Citizen ${verifiedPhone.slice(-4)}`;
      const insertResult = await db.query(
        `INSERT INTO users (name, phone, role, location, points, is_verified)
         VALUES ($1, $2, 'user', 'Mumbai', 0, TRUE)
         RETURNING id, name, email, phone, role, location, points, is_verified, created_at`,
        [displayName, verifiedPhone]
      );
      user = insertResult.rows[0];
    } else {
      user = userQuery.rows[0];
      // Mark verified and update name if previously generic
      let updateSql = 'UPDATE users SET is_verified = TRUE';
      const updateParams = [user.id];

      if (name && name.trim().length > 0 && user.name.startsWith('Citizen ')) {
        updateParams.push(name.trim());
        updateSql += `, name = $2 WHERE id = $1`;
      } else {
        updateSql += ` WHERE id = $1`;
      }

      updateSql += ' RETURNING id, name, email, phone, role, location, points, is_verified, created_at';
      const updateRes = await db.query(updateSql, updateParams);
      user = updateRes.rows[0];
      delete user.password_hash;
    }

    const token = jwt.sign(
      { id: user.id, role: user.role, name: user.name, jti: crypto.randomBytes(16).toString('hex') },
      process.env.JWT_SECRET || 'civicconnect_super_secret_jwt_key_2026',
      { expiresIn: '30d' }
    );

    // Record session in auth_sessions
    try {
      const tokenH = hashToken(token);
      const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
      await db.query(
        `INSERT INTO auth_sessions (user_id, token_hash, ip_address, user_agent, expires_at)
         VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (token_hash) DO NOTHING`,
        [user.id, tokenH, req.ip || req.connection?.remoteAddress, req.headers['user-agent'] || null, expiresAt]
      );
    } catch (sessionErr) {
      console.warn('[AUTH] Could not record auth_session on OTP verify:', sessionErr.message);
    }

    // Record OTP verification in audit_logs
    try {
      await db.query(
        `INSERT INTO audit_logs (actor_id, action, entity_type, entity_id, new_values, ip_address)
         VALUES ($1, 'USER_LOGIN_OTP', 'users', $2, $3, $4)`,
        [
          user.id,
          user.id,
          JSON.stringify({ phone: verifiedPhone }),
          req.ip || req.connection?.remoteAddress,
        ]
      );
    } catch (auditErr) {
      console.warn('[AUTH] Could not record OTP login audit log:', auditErr.message);
    }

    res.json({
      success: true,
      message: 'Phone verified successfully',
      token,
      user,
    });
  } catch (err) {
    console.error('Error verifying OTP:', err.message);
    res.status(500).json({ success: false, message: 'Server error during verification' });
  }
});

/**
 * @route   GET /api/auth/profile
 * @desc    Get currently authenticated citizen profile
 */
router.get('/profile', authenticateToken, async (req, res) => {
  try {
    const result = await db.query(
      'SELECT id, name, email, phone, role, location, points, is_verified, created_at FROM users WHERE id = $1',
      [req.user.id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'User not found' });
    }

    res.json({
      success: true,
      user: result.rows[0],
    });
  } catch (err) {
    console.error('Error fetching profile:', err.message);
    res.status(500).json({ success: false, message: 'Server error' });
  }
});

/**
 * @route   PUT /api/auth/profile
 * @desc    Update citizen profile (name and location)
 */
router.put('/profile', authenticateToken, async (req, res) => {
  try {
    const { name, location } = req.body;
    const userId = req.user.id;

    const result = await db.query(
      `UPDATE users
       SET name = COALESCE($1, name),
           location = COALESCE($2, location),
           updated_at = CURRENT_TIMESTAMP
       WHERE id = $3
       RETURNING id, name, email, phone, role, location, points, is_verified, created_at`,
      [name ? name.trim() : null, location ? location.trim() : null, userId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'User not found' });
    }

    res.json({
      success: true,
      message: 'Profile updated successfully',
      user: result.rows[0],
    });
  } catch (err) {
    console.error('Error updating profile:', err.message);
    res.status(500).json({ success: false, message: 'Server error' });
  }
});

/**
 * @route   GET /api/auth/me
 * @desc    Get currently authenticated user details including role, staff profile, and department
 */
router.get('/me', authenticateToken, async (req, res) => {
  try {
    const userRes = await db.query(
      `SELECT u.id, u.name, u.email, u.phone, u.role, u.location, u.points, u.is_verified, u.created_at,
              sp.department_id, sp.employee_id, sp.jurisdiction, sp.skills, sp.max_capacity, sp.current_load,
              d.name as department_name, d.code as department_code
       FROM users u
       LEFT JOIN staff_profiles sp ON u.id = sp.user_id
       LEFT JOIN departments d ON sp.department_id = d.id
       WHERE u.id = $1`,
      [req.user.id]
    );

    if (userRes.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'User not found' });
    }

    res.json({
      success: true,
      user: userRes.rows[0],
    });
  } catch (err) {
    console.error('Error fetching me profile:', err.message);
    res.status(500).json({ success: false, message: 'Server error' });
  }
});

/**
 * @route   POST /api/auth/logout
 * @desc    Revoke current JWT session and log out
 */
router.post('/logout', authenticateToken, async (req, res) => {
  try {
    if (req.rawToken) {
      const tokenH = hashToken(req.rawToken);
      await db.query(
        'UPDATE auth_sessions SET is_revoked = TRUE WHERE token_hash = $1',
        [tokenH]
      );
    }

    try {
      await db.query(
        `INSERT INTO audit_logs (actor_id, action, entity_type, entity_id, ip_address)
         VALUES ($1, 'USER_LOGOUT', 'users', $2, $3)`,
        [req.user.id, req.user.id, req.ip || req.connection?.remoteAddress]
      );
    } catch (_) {}

    res.json({
      success: true,
      message: 'Logged out successfully. Session has been revoked.',
    });
  } catch (err) {
    console.error('Error during logout:', err.message);
    res.status(500).json({ success: false, message: 'Server error during logout' });
  }
});

/**
 * @route   POST /api/auth/forgot-password
 * @desc    Generate password recovery OTP and email it via Resend.
 *          Returns a generic success message regardless of whether the email exists
 *          to prevent email enumeration.
 */
router.post('/forgot-password', async (req, res) => {
  try {
    const { email } = req.body;

    if (!email || !isValidEmail(email)) {
      return res.status(400).json({
        success: false,
        message: 'Please provide a valid registered email address.',
      });
    }

    const cleanEmail = email.trim().toLowerCase();

    // Check if user exists with this email
    const userQuery = await db.query(
      'SELECT id, name, email FROM users WHERE LOWER(email) = $1',
      [cleanEmail]
    );

    // Generic privacy-preserving message
    const genericResponse = {
      success: true,
      message: 'If an account with that email exists, a password reset code has been sent.',
    };

    if (userQuery.rows.length === 0) {
      // Return generic success to prevent email enumeration
      return res.json(genericResponse);
    }

    // Cooldown check: 60 seconds
    const recentChallenge = await db.query(
      `SELECT created_at FROM otp_challenges 
       WHERE email = $1 AND purpose = 'password_reset' AND created_at > (CURRENT_TIMESTAMP - INTERVAL '60 seconds')
       ORDER BY created_at DESC LIMIT 1`,
      [cleanEmail]
    );

    if (recentChallenge.rows.length > 0) {
      const elapsedMs = Date.now() - new Date(recentChallenge.rows[0].created_at).getTime();
      const waitSecs = Math.max(1, Math.ceil((60000 - elapsedMs) / 1000));
      return res.status(429).json({
        success: false,
        message: `Please wait ${waitSecs} seconds before requesting another reset code.`,
        cooldownSeconds: waitSecs,
      });
    }

    // Invalidate previous unconsumed password reset challenges for this email
    await db.query(
      `UPDATE otp_challenges 
       SET is_consumed = TRUE 
       WHERE email = $1 AND purpose = 'password_reset' AND is_consumed = FALSE`,
      [cleanEmail]
    );

    // Generate cryptographically secure random 6-digit OTP
    const otpInt = crypto.randomInt(100000, 1000000);
    const otp = otpInt.toString();

    // Unique verification ID
    const verificationId = 'reset_' + crypto.randomBytes(16).toString('hex');

    // Hash the OTP with bcrypt (10 rounds) before storing in PostgreSQL
    const otpHash = await bcrypt.hash(otp, 10);

    // 10 minutes expiry for password reset
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000);

    // Store challenge in PostgreSQL
    await db.query(
      `INSERT INTO otp_challenges (verification_id, email, otp_hash, purpose, attempts, max_attempts, is_consumed, expires_at)
       VALUES ($1, $2, $3, 'password_reset', 0, 5, FALSE, $4)`,
      [verificationId, cleanEmail, otpHash, expiresAt]
    );

    // Send email via Resend SDK
    let emailResult;
    try {
      emailResult = await sendPasswordResetEmail(cleanEmail, otp);
    } catch (mailErr) {
      console.error('[AUTH-FORGOT-PASSWORD] ❌ Resend error:', mailErr.message);
      // Clean up challenge on failure
      await db.query(
        'UPDATE otp_challenges SET is_consumed = TRUE WHERE verification_id = $1',
        [verificationId]
      );
      return res.status(502).json({
        success: false,
        message: `Failed to deliver recovery email: ${mailErr.message}`,
      });
    }

    res.json({
      success: true,
      message: 'If an account with that email exists, a password reset code has been sent.',
      verificationId,
      expiresIn: 600,
      devOtp: process.env.NODE_ENV === 'production' ? undefined : emailResult.devOtp,
    });
  } catch (err) {
    console.error('Error in forgot-password:', err.message);
    res.status(500).json({ success: false, message: 'Server error processing password recovery' });
  }
});

/**
 * @route   POST /api/auth/verify-reset-otp
 * @desc    Validate password reset OTP against bcrypt hash in PostgreSQL,
 *          enforce attempt limits, expiration, and issue short-lived reset token.
 */
router.post('/verify-reset-otp', async (req, res) => {
  try {
    const { verificationId, email, otp } = req.body;

    if ((!verificationId && !email) || !otp) {
      return res.status(400).json({
        success: false,
        message: 'Verification ID (or email) and OTP code are required.',
      });
    }

    let challengeRes;
    if (verificationId) {
      challengeRes = await db.query(
        `SELECT * FROM otp_challenges WHERE verification_id = $1 AND purpose = 'password_reset'`,
        [verificationId]
      );
    } else {
      const cleanEmail = email.trim().toLowerCase();
      challengeRes = await db.query(
        `SELECT * FROM otp_challenges WHERE email = $1 AND purpose = 'password_reset' ORDER BY created_at DESC LIMIT 1`,
        [cleanEmail]
      );
    }

    if (challengeRes.rows.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'Invalid or expired password reset session. Please request a new code.',
      });
    }

    const challenge = challengeRes.rows[0];

    // Single-use check
    if (challenge.is_consumed) {
      return res.status(400).json({
        success: false,
        message: 'This reset code has already been used. Please request a new one.',
      });
    }

    // Expiration check
    if (new Date() > new Date(challenge.expires_at)) {
      await db.query(`UPDATE otp_challenges SET is_consumed = TRUE WHERE id = $1`, [challenge.id]);
      return res.status(400).json({
        success: false,
        message: 'Reset code has expired. Please request a new code.',
      });
    }

    // Max attempt limit
    if (challenge.attempts >= challenge.max_attempts) {
      await db.query(`UPDATE otp_challenges SET is_consumed = TRUE WHERE id = $1`, [challenge.id]);
      return res.status(429).json({
        success: false,
        message: 'Too many incorrect attempts. This reset session has been locked. Please request a new code.',
      });
    }

    // Compare submitted OTP with stored bcrypt hash
    const isMatch = await bcrypt.compare(otp.trim(), challenge.otp_hash);

    if (!isMatch) {
      const newAttempts = challenge.attempts + 1;
      const remainingAttempts = Math.max(0, challenge.max_attempts - newAttempts);

      if (remainingAttempts === 0) {
        await db.query(
          `UPDATE otp_challenges SET attempts = $1, is_consumed = TRUE WHERE id = $2`,
          [newAttempts, challenge.id]
        );
        return res.status(429).json({
          success: false,
          message: 'Too many incorrect attempts. This reset session has been locked. Please request a new code.',
        });
      } else {
        await db.query(
          `UPDATE otp_challenges SET attempts = $1 WHERE id = $2`,
          [newAttempts, challenge.id]
        );
        return res.status(400).json({
          success: false,
          message: `Invalid reset code. (${remainingAttempts} attempts remaining)`,
          remainingAttempts,
        });
      }
    }

    // Mark challenge consumed
    await db.query(`UPDATE otp_challenges SET is_consumed = TRUE WHERE id = $1`, [challenge.id]);

    // Issue short-lived reset token (valid for 15 minutes)
    const resetToken = jwt.sign(
      { email: challenge.email, purpose: 'password_reset' },
      process.env.JWT_SECRET || 'civicconnect_super_secret_jwt_key_2026',
      { expiresIn: '15m' }
    );

    res.json({
      success: true,
      message: 'Reset code verified successfully. You may now set your new password.',
      resetToken,
    });
  } catch (err) {
    console.error('Error verifying reset OTP:', err.message);
    res.status(500).json({ success: false, message: 'Server error during OTP verification' });
  }
});

/**
 * @route   POST /api/auth/reset-password
 * @desc    Save new bcrypt password hash after valid reset token verification.
 */
router.post('/reset-password', async (req, res) => {
  try {
    const { resetToken, newPassword } = req.body;

    if (!resetToken || !newPassword) {
      return res.status(400).json({
        success: false,
        message: 'Reset token and new password are required.',
      });
    }

    if (newPassword.trim().length < 6) {
      return res.status(400).json({
        success: false,
        message: 'New password must be at least 6 characters long.',
      });
    }

    // Verify resetToken
    let decoded;
    try {
      decoded = jwt.verify(
        resetToken,
        process.env.JWT_SECRET || 'civicconnect_super_secret_jwt_key_2026'
      );
    } catch (tokenErr) {
      return res.status(401).json({
        success: false,
        message: 'Invalid or expired password reset session. Please request a new reset code.',
      });
    }

    if (decoded.purpose !== 'password_reset' || !decoded.email) {
      return res.status(403).json({
        success: false,
        message: 'Invalid reset token authorization.',
      });
    }

    // Hash new password using bcrypt
    const passwordHash = await bcrypt.hash(newPassword, 10);

    // Update user password hash in PostgreSQL
    const updateResult = await db.query(
      `UPDATE users
       SET password_hash = $1, updated_at = CURRENT_TIMESTAMP
       WHERE LOWER(email) = LOWER($2)
       RETURNING id, name, email, phone, role, location, points, is_verified`,
      [passwordHash, decoded.email]
    );

    if (updateResult.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'User account not found.',
      });
    }

    res.json({
      success: true,
      message: 'Password reset successful. You can now log in with your new password.',
    });
  } catch (err) {
    console.error('Error resetting password:', err.message);
    res.status(500).json({ success: false, message: 'Server error during password reset' });
  }
});

module.exports = router;

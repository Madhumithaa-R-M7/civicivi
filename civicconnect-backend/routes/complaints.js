const express = require('express');
const router = express.Router();
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const db = require('../db');
const { optionalAuth, authenticateToken } = require('../middleware/auth');
const {
  transitionComplaintStatus,
  getComplaintHistory,
  normalizeState,
  COMPLAINT_STATES,
} = require('../services/fsm');
const {
  processAndStoreImage,
  verifyImageIntegrity,
  findSimilarImages,
  computeSha256,
  computePHash,
  hammingDistance,
} = require('../services/image_processing');
const { classifyComplaint } = require('../services/nlp_classifier');
const {
  haversineDistance,
  routeDepartment,
  calculatePriorityScore,
  checkSpatiotemporalDuplicate,
} = require('../services/spatial_priority');

// Setup multer storage for complaint images
const uploadDir = path.join(__dirname, '..', 'uploads');
if (!fs.existsSync(uploadDir)) {
  fs.mkdirSync(uploadDir, { recursive: true });
}

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, uploadDir);
  },
  filename: (req, file, cb) => {
    // Whitelist safe image extensions only
    let rawExt = path.extname(file.originalname).toLowerCase();
    if (!['.jpg', '.jpeg', '.png', '.webp'].includes(rawExt)) {
      if (file.mimetype === 'image/jpeg') rawExt = '.jpg';
      else if (file.mimetype === 'image/png') rawExt = '.png';
      else if (file.mimetype === 'image/webp') rawExt = '.webp';
      else rawExt = '.jpg';
    }
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1e9);
    cb(null, 'complaint-' + uniqueSuffix + rawExt);
  },
});

const upload = multer({
  storage,
  limits: { fileSize: 10 * 1024 * 1024 }, // 10MB limit
  fileFilter: (req, file, cb) => {
    const allowedMime = ['image/jpeg', 'image/png', 'image/webp', 'image/jpg'];
    if (allowedMime.includes(file.mimetype.toLowerCase())) {
      cb(null, true);
    } else {
      cb(new Error('Only image files (JPEG, PNG, WEBP) are allowed.'), false);
    }
  },
});

/**
 * @route   POST /api/complaints
 * @desc    Submit a new civic complaint with image upload & GPS coordinates
 *          Strictly authenticated via JWT token.
 */
router.post('/', authenticateToken, upload.single('image'), async (req, res) => {
  try {
    const {
      category = 'General',
      description = '',
      priority = 'Medium',
      location = '',
      latitude,
      longitude,
      locationAccuracy,
      location_accuracy,
      locationCapturedAt,
      location_captured_at,
    } = req.body;

    let finalCategory = category ? category.trim() : '';
    const textClassification = classifyComplaint(description);
    if (!finalCategory || finalCategory.toLowerCase().includes('other') || finalCategory.toLowerCase().includes('general')) {
      if (textClassification.isConfident) {
        finalCategory = textClassification.category;
      } else if (!finalCategory) {
        finalCategory = 'General Civic Issue';
      }
    }

    if (!description || description.trim().length === 0) {
      return res.status(400).json({ success: false, message: 'Description is required' });
    }

    // Authenticated user identity from verified JWT
    const userId = req.user.id;

    let imageUrl = '';
    if (req.file) {
      imageUrl = `/uploads/${req.file.filename}`;
    } else if (req.body.imageUrl && typeof req.body.imageUrl === 'string') {
      // Disallow client arbitrary server path injection
      if (req.body.imageUrl.startsWith('/uploads/') || req.body.imageUrl.startsWith('http')) {
        imageUrl = req.body.imageUrl;
      }
    }

    const lat = latitude != null && latitude !== '' ? parseFloat(latitude) : null;
    const lng = longitude != null && longitude !== '' ? parseFloat(longitude) : null;
    const rawAccuracy = locationAccuracy != null ? locationAccuracy : location_accuracy;
    const accuracy = rawAccuracy != null && rawAccuracy !== '' ? parseFloat(rawAccuracy) : null;

    let capturedAt = locationCapturedAt || location_captured_at;
    if (capturedAt) {
      try {
        capturedAt = new Date(capturedAt).toISOString();
      } catch (_) {
        capturedAt = new Date().toISOString();
      }
    } else if (lat != null && lng != null) {
      capturedAt = new Date().toISOString();
    } else {
      capturedAt = null;
    }

    // Algorithm 9: Department routing lookup based on category
    const routed = routeDepartment(finalCategory);
    let departmentId = null;
    try {
      const deptRes = await db.query(
        `SELECT id FROM departments 
         WHERE code = $1 OR LOWER(name) LIKE $2 LIMIT 1`,
        [routed.departmentCode, `%${routed.departmentName.toLowerCase().split(' ')[0]}%`]
      );
      if (deptRes.rows.length > 0) {
        departmentId = deptRes.rows[0].id;
      }
    } catch (_) {}

    // Algorithm 11: Calculate count of nearby complaints within 200m using Haversine formula
    let nearbyCount = 0;
    if (lat != null && lng != null) {
      try {
        const nearRes = await db.query(
          `SELECT latitude, longitude FROM complaints 
           WHERE latitude IS NOT NULL AND longitude IS NOT NULL
             AND status NOT IN ('RESOLVED', 'CLOSED', 'REJECTED')
             AND created_at >= (CURRENT_TIMESTAMP - INTERVAL '30 days')`
        );
        for (const r of nearRes.rows) {
          const d = haversineDistance(lat, lng, r.latitude, r.longitude);
          if (d <= 200) nearbyCount++;
        }
      } catch (_) {}
    }

    // Algorithm 8: Weighted Priority Scoring (P = 0.25S + 0.20U + 0.15C + 0.15G + 0.10R + 0.15A)
    const priorityCalc = calculatePriorityScore({
      priority,
      description,
      category: finalCategory,
      nearbyCount,
      hasGps: lat != null && lng != null,
    });
    const priorityScore = priorityCalc.score;

    const result = await db.query(
      `INSERT INTO complaints 
       (user_id, category, description, priority, location, latitude, longitude, location_accuracy, location_captured_at, status, image_url, department_id, priority_score)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'SUBMITTED', $10, $11, $12)
       RETURNING *`,
      [userId, finalCategory, description.trim(), priority, location.trim(), lat, lng, accuracy, capturedAt, imageUrl, departmentId, priorityScore]
    );

    const complaint = result.rows[0];

    // Record initial status in status_history (FSM Audit Trail)
    try {
      await db.query(
        `INSERT INTO status_history (complaint_id, from_status, to_status, changed_by, reason)
         VALUES ($1, 'NONE', 'SUBMITTED', $2, 'Initial complaint registration')`,
        [complaint.id, userId]
      );
    } catch (histErr) {
      console.warn('[COMPLAINTS] Could not record status_history:', histErr.message);
    }

    // Initialize SLA record (24h response, 72h resolution deadline)
    try {
      const responseDeadline = new Date(Date.now() + 24 * 60 * 60 * 1000);
      const resolutionDeadline = new Date(Date.now() + 72 * 60 * 60 * 1000);
      await db.query(
        `INSERT INTO sla_records (complaint_id, response_deadline, resolution_deadline)
         VALUES ($1, $2, $3)
         ON CONFLICT (complaint_id) DO NOTHING`,
        [complaint.id, responseDeadline, resolutionDeadline]
      );
    } catch (slaErr) {
      console.warn('[COMPLAINTS] Could not record sla_record:', slaErr.message);
    }

    // Record audit log
    try {
      await db.query(
        `INSERT INTO audit_logs (actor_id, action, entity_type, entity_id, new_values)
         VALUES ($1, 'COMPLAINT_SUBMITTED', 'complaints', $2, $3)`,
        [userId, complaint.id, JSON.stringify({ category, priority, location, department_id: departmentId })]
      );
    } catch (auditErr) {
      console.warn('[COMPLAINTS] Could not record audit log:', auditErr.message);
    }

    // Award points to authenticated citizen
    let earnedPoints = 10; // Base points for reporting
    if (lat != null && lng != null) earnedPoints += 5; // Bonus for GPS location
    if (imageUrl) earnedPoints += 5; // Bonus for photo evidence

    // Process image evidence with SHA-256 and pHash algorithms
    let imageAnalysis = null;
    if (req.file) {
      try {
        imageAnalysis = await processAndStoreImage({
          complaintId: complaint.id,
          file: req.file,
          storagePath: imageUrl,
        });
      } catch (imgErr) {
        console.warn('[COMPLAINTS] Could not process image hashing:', imgErr.message);
      }
    }

    // Update user points
    await db.query('UPDATE users SET points = points + $1 WHERE id = $2', [earnedPoints, userId]);

    // Log points
    await db.query(
      'INSERT INTO points_log (user_id, complaint_id, points, reason) VALUES ($1, $2, $3, $4)',
      [userId, complaint.id, earnedPoints, `Reported issue: ${category}`]
    );

    // Create notification
    await db.query(
      `INSERT INTO notifications (user_id, complaint_id, title, description, type)
       VALUES ($1, $2, $3, $4, 'submission')`,
      [
        userId,
        complaint.id,
        'Issue Registered Successfully',
        `Your report for "${category}" at ${location || 'your location'} has been logged. +${earnedPoints} Civic Points!`,
      ]
    );

    // Algorithm 7: Spatiotemporal Multi-Modal Duplicate Detection
    let spatiotemporalDuplicate = null;
    if (lat != null && lng != null) {
      try {
        spatiotemporalDuplicate = await checkSpatiotemporalDuplicate({
          latitude: lat,
          longitude: lng,
          category: finalCategory,
          description: description.trim(),
          phash: imageAnalysis ? imageAnalysis.phash : null,
          radiusMeters: 150,
          daysWindow: 30,
          excludeComplaintId: complaint.id,
        });

        if (spatiotemporalDuplicate.isDuplicate && spatiotemporalDuplicate.duplicateOfId) {
          await db.query(
            `UPDATE complaints
             SET duplicate_of_id = COALESCE(duplicate_of_id, $1),
                 duplicate_score = GREATEST(COALESCE(duplicate_score, 0), $2),
                 updated_at = CURRENT_TIMESTAMP
             WHERE id = $3`,
            [spatiotemporalDuplicate.duplicateOfId, spatiotemporalDuplicate.confidenceScore / 100, complaint.id]
          );
        }
      } catch (spatErr) {
        console.warn('[COMPLAINTS] Could not run spatiotemporal duplicate check:', spatErr.message);
      }
    }

    res.status(201).json({
      success: true,
      message: 'Complaint submitted successfully',
      complaint: {
        ...complaint,
        priority_score: priorityScore,
        category: finalCategory,
      },
      imageAnalysis: imageAnalysis ? {
        sha256: imageAnalysis.sha256,
        phash: imageAnalysis.phash,
        isExactDuplicate: imageAnalysis.isExactDuplicate,
        isVisualDuplicate: imageAnalysis.isVisualDuplicate,
        duplicateOfId: imageAnalysis.exactMatch ? imageAnalysis.exactMatch.complaint_id : (imageAnalysis.bestVisualMatch ? imageAnalysis.bestVisualMatch.complaint_id : null),
        hammingDistance: imageAnalysis.hammingDistance,
        similarityScore: imageAnalysis.similarityScore,
      } : null,
      classification: textClassification,
      priorityAnalysis: priorityCalc,
      spatiotemporalDuplicate,
    });
  } catch (err) {
    console.error('Error submitting complaint:', err.message);
    res.status(500).json({ success: false, message: 'Internal server error during complaint submission' });
  }
});

/**
 * @route   GET /api/complaints
 * @desc    Get complaints. If onlyMine=true, requires JWT authentication and only returns owner's records.
 */
router.get('/', optionalAuth, async (req, res) => {
  try {
    const { status, onlyMine } = req.query;

    if (onlyMine === 'true') {
      if (!req.user) {
        return res.status(401).json({ success: false, message: 'Authentication required to view your personal reports' });
      }

      let query = `
        SELECT c.id, c.user_id, c.category, c.description, c.priority, c.location, 
               c.latitude, c.longitude, c.location_accuracy, c.location_captured_at,
               c.status, c.image_url, c.resolution_notes, 
               c.created_at, c.updated_at, u.name as user_name
        FROM complaints c 
        LEFT JOIN users u ON c.user_id = u.id 
        WHERE c.user_id = $1
      `;
      const params = [req.user.id];

      if (status) {
        const norm = normalizeState(status);
        params.push(norm);
        params.push(status);
        query += ` AND (c.status = $${params.length - 1} OR c.status = $${params.length})`;
      }

      query += ' ORDER BY c.created_at DESC';

      const result = await db.query(query, params);
      return res.json({
        success: true,
        count: result.rows.length,
        complaints: result.rows,
      });
    }

    // Public community complaints list
    let query = `
      SELECT c.id, c.category, c.description, c.priority, c.location, 
             c.latitude, c.longitude, c.location_accuracy, c.location_captured_at,
             c.status, c.image_url, c.created_at, 
             u.name as user_name
      FROM complaints c 
      LEFT JOIN users u ON c.user_id = u.id 
      WHERE 1=1
    `;
    const params = [];

    if (status) {
      const norm = normalizeState(status);
      params.push(norm);
      params.push(status);
      query += ` AND (c.status = $${params.length - 1} OR c.status = $${params.length})`;
    }

    query += ' ORDER BY c.created_at DESC';

    const result = await db.query(query, params);

    res.json({
      success: true,
      count: result.rows.length,
      complaints: result.rows,
    });
  } catch (err) {
    console.error('Error fetching complaints:', err.message);
    res.status(500).json({ success: false, message: 'Internal server error' });
  }
});

/**
 * @route   GET /api/complaints/nearby
 * @desc    Find complaints within radius using the Haversine formula (Algorithm 11)
 */
router.get('/nearby', async (req, res) => {
  try {
    const lat = parseFloat(req.query.lat || req.query.latitude);
    const lng = parseFloat(req.query.lng || req.query.longitude);
    const radiusMeters = parseFloat(req.query.radius || req.query.radiusMeters || '1000');
    const category = req.query.category;
    const status = req.query.status;

    if (isNaN(lat) || isNaN(lng)) {
      return res.status(400).json({ success: false, message: 'Valid lat and lng query parameters are required' });
    }

    let query = `
      SELECT c.id, c.category, c.description, c.priority, c.priority_score,
             c.location, c.latitude, c.longitude, c.status, c.image_url,
             c.created_at, u.name as user_name
      FROM complaints c
      LEFT JOIN users u ON c.user_id = u.id
      WHERE c.latitude IS NOT NULL AND c.longitude IS NOT NULL
    `;
    const params = [];

    if (category) {
      params.push(`%${category.toLowerCase()}%`);
      query += ` AND LOWER(c.category) LIKE $${params.length}`;
    }
    if (status) {
      params.push(status);
      query += ` AND c.status = $${params.length}`;
    }

    query += ' ORDER BY c.created_at DESC LIMIT 300';

    const result = await db.query(query, params);
    const nearby = [];

    for (const row of result.rows) {
      const distance = haversineDistance(lat, lng, row.latitude, row.longitude);
      if (distance <= radiusMeters) {
        nearby.push({
          ...row,
          distanceMeters: distance,
        });
      }
    }

    // Sort by proximity (closest first)
    nearby.sort((a, b) => a.distanceMeters - b.distanceMeters);

    res.json({
      success: true,
      count: nearby.length,
      radiusMeters,
      complaints: nearby,
    });
  } catch (err) {
    console.error('Error fetching nearby complaints:', err.message);
    res.status(500).json({ success: false, message: 'Internal server error fetching nearby complaints' });
  }
});

/**
 * @route   POST /api/complaints/classify
 * @desc    Predict civic category and department from description text (Algorithm 1)
 */
router.post('/classify', (req, res) => {
  try {
    const { text, description } = req.body;
    const input = text || description || '';

    if (!input || input.trim().length === 0) {
      return res.status(400).json({ success: false, message: 'Text or description is required for classification' });
    }

    const prediction = classifyComplaint(input);
    res.json({
      success: true,
      ...prediction,
    });
  } catch (err) {
    console.error('Error in text classification:', err.message);
    res.status(500).json({ success: false, message: 'Failed to classify text' });
  }
});

/**
 * @route   POST /api/complaints/check-duplicate
 * @desc    Multi-modal pre-submission duplicate screening (GPS + Text TF-IDF + Image)
 */
router.post('/check-duplicate', upload.single('image'), async (req, res) => {
  try {
    const { latitude, longitude, category, description } = req.body;
    const lat = latitude != null && latitude !== '' ? parseFloat(latitude) : null;
    const lng = longitude != null && longitude !== '' ? parseFloat(longitude) : null;

    let sha256 = null;
    let phash = null;
    let exactMatch = null;
    let visualMatches = [];

    if (req.file) {
      const buffer = req.file.buffer || await fs.promises.readFile(req.file.path);
      sha256 = computeSha256(buffer);
      phash = await computePHash(buffer);

      const exactRes = await db.query(
        `SELECT ci.id, ci.complaint_id, ci.storage_path, c.category, c.status, c.location
         FROM complaint_images ci
         JOIN complaints c ON ci.complaint_id = c.id
         WHERE ci.sha256_hash = $1
         ORDER BY ci.created_at ASC LIMIT 1`,
        [sha256]
      );
      if (exactRes.rows.length > 0) exactMatch = exactRes.rows[0];

      if (phash) {
        visualMatches = await findSimilarImages(phash, { threshold: 10, limit: 5 });
      }

      // Cleanup temp upload
      if (req.file.path && fs.existsSync(req.file.path)) {
        try { await fs.promises.unlink(req.file.path); } catch (_) {}
      }
    }

    // Run spatiotemporal & text duplicate check
    let spatiotemporal = { isDuplicate: false, duplicateCandidates: [], topMatch: null, confidenceScore: 0 };
    if (lat != null && lng != null) {
      spatiotemporal = await checkSpatiotemporalDuplicate({
        latitude: lat,
        longitude: lng,
        category: category || '',
        description: description || '',
        phash,
        radiusMeters: 150,
        daysWindow: 30,
      });
    }

    const isDuplicate = exactMatch != null || visualMatches.length > 0 || spatiotemporal.isDuplicate;
    const highestConfidence = Math.max(
      exactMatch ? 100 : 0,
      visualMatches.length > 0 ? visualMatches[0].similarity_score : 0,
      spatiotemporal.confidenceScore
    );

    res.json({
      success: true,
      isDuplicate,
      confidenceScore: highestConfidence,
      exactMatch,
      visualMatches,
      spatiotemporal,
      warningMessage: isDuplicate
        ? 'A similar civic issue has already been reported nearby. Submitting will link your report to expedite resolution.'
        : null,
    });
  } catch (err) {
    console.error('Error screening for duplicates:', err.message);
    res.status(500).json({ success: false, message: 'Internal server error screening duplicate' });
  }
});

/**
 * @route   GET /api/complaints/:id
 * @desc    Get single complaint details with location metadata
 */
router.get('/:id', async (req, res) => {
  try {
    const id = parseInt(req.params.id, 10);
    if (isNaN(id)) {
      return res.status(400).json({ success: false, message: 'Invalid complaint ID' });
    }

    const result = await db.query(
      `SELECT c.id, c.user_id, c.category, c.description, c.priority, c.location, 
              c.latitude, c.longitude, c.location_accuracy, c.location_captured_at,
              c.status, c.image_url, c.resolution_notes, 
              c.created_at, c.updated_at, u.name as user_name
       FROM complaints c
       LEFT JOIN users u ON c.user_id = u.id
       WHERE c.id = $1`,
      [id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Complaint not found' });
    }

    res.json({
      success: true,
      complaint: result.rows[0],
    });
  } catch (err) {
    console.error('Error fetching complaint:', err.message);
    res.status(500).json({ success: false, message: 'Internal server error' });
  }
});

/**
 * @route   PUT /api/complaints/:id
 * @desc    Update complaint details (owner or staff/admin only)
 */
router.put('/:id', authenticateToken, async (req, res) => {
  try {
    const id = parseInt(req.params.id, 10);
    if (isNaN(id)) {
      return res.status(400).json({ success: false, message: 'Invalid complaint ID' });
    }

    const existing = await db.query('SELECT * FROM complaints WHERE id = $1', [id]);
    if (existing.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Complaint not found' });
    }

    const complaint = existing.rows[0];
    const isOwner = complaint.user_id === req.user.id;
    const isStaffOrAdmin = req.user.role === 'admin' || req.user.role === 'staff';

    if (!isOwner && !isStaffOrAdmin) {
      return res.status(403).json({
        success: false,
        message: 'Forbidden: You do not have permission to modify this complaint',
      });
    }

    const { description, category, priority } = req.body;
    const result = await db.query(
      `UPDATE complaints
       SET description = COALESCE($1, description),
           category = COALESCE($2, category),
           priority = COALESCE($3, priority),
           updated_at = CURRENT_TIMESTAMP
       WHERE id = $4
       RETURNING *`,
      [description || null, category || null, priority || null, id]
    );

    res.json({
      success: true,
      message: 'Complaint updated successfully',
      complaint: result.rows[0],
    });
  } catch (err) {
    console.error('Error modifying complaint:', err.message);
    res.status(500).json({ success: false, message: 'Internal server error' });
  }
});

/**
 * @route   PATCH /api/complaints/:id/status
 * @desc    Update complaint status (staff/admin or complaint owner only)
 */
router.patch('/:id/status', authenticateToken, async (req, res) => {
  try {
    const id = parseInt(req.params.id, 10);
    if (isNaN(id)) {
      return res.status(400).json({ success: false, message: 'Invalid complaint ID' });
    }

    const { status, resolutionNotes, assignedTo, reason, departmentId } = req.body;

    if (!status) {
      return res.status(400).json({ success: false, message: 'Status is required' });
    }

    const updated = await transitionComplaintStatus({
      complaintId: id,
      targetStatus: status,
      actor: req.user,
      reason: reason || resolutionNotes,
      resolutionNotes: resolutionNotes,
      assignedTo: assignedTo ? parseInt(assignedTo, 10) : null,
      departmentId: departmentId ? parseInt(departmentId, 10) : null,
    });

    res.json({
      success: true,
      message: 'Status updated successfully',
      complaint: updated,
    });
  } catch (err) {
    console.error('Error updating complaint status:', err.message);
    const statusCode = err.status || 500;
    res.status(statusCode).json({
      success: false,
      message: err.message || 'Internal server error',
    });
  }
});

/**
 * @route   GET /api/complaints/:id/history
 * @desc    Get chronological lifecycle and audit timeline for a complaint
 */
router.get('/:id/history', async (req, res) => {
  try {
    const id = parseInt(req.params.id, 10);
    if (isNaN(id)) {
      return res.status(400).json({ success: false, message: 'Invalid complaint ID' });
    }

    const history = await getComplaintHistory(id);
    res.json({
      success: true,
      count: history.length,
      history,
    });
  } catch (err) {
    console.error('Error fetching complaint history:', err.message);
    res.status(500).json({ success: false, message: 'Internal server error' });
  }
});

/**
 * @route   POST /api/complaints/:id/images
 * @desc    Upload additional evidence photo for an existing complaint
 */
router.post('/:id/images', authenticateToken, upload.single('image'), async (req, res) => {
  try {
    const id = parseInt(req.params.id, 10);
    if (isNaN(id)) {
      return res.status(400).json({ success: false, message: 'Invalid complaint ID' });
    }

    if (!req.file) {
      return res.status(400).json({ success: false, message: 'Image file is required' });
    }

    const existing = await db.query('SELECT * FROM complaints WHERE id = $1', [id]);
    if (existing.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Complaint not found' });
    }

    const complaint = existing.rows[0];
    const isOwner = complaint.user_id === req.user.id;
    const isStaffOrAdmin = req.user.role === 'admin' || req.user.role === 'staff' || req.user.role === 'super_admin';

    if (!isOwner && !isStaffOrAdmin) {
      return res.status(403).json({ success: false, message: 'Forbidden: You cannot upload evidence to this complaint' });
    }

    const storagePath = `/uploads/${req.file.filename}`;
    const analysis = await processAndStoreImage({
      complaintId: id,
      file: req.file,
      storagePath,
    });

    res.status(201).json({
      success: true,
      message: 'Image evidence added successfully',
      image: analysis.imageRecord,
      analysis: {
        sha256: analysis.sha256,
        phash: analysis.phash,
        isExactDuplicate: analysis.isExactDuplicate,
        isVisualDuplicate: analysis.isVisualDuplicate,
        duplicateOfId: analysis.exactMatch ? analysis.exactMatch.complaint_id : (analysis.bestVisualMatch ? analysis.bestVisualMatch.complaint_id : null),
        hammingDistance: analysis.hammingDistance,
        similarityScore: analysis.similarityScore,
      },
    });
  } catch (err) {
    console.error('Error adding complaint image:', err.message);
    res.status(500).json({ success: false, message: 'Internal server error adding image' });
  }
});

/**
 * @route   GET /api/complaints/:id/images
 * @desc    Retrieve all evidence images and cryptographic hashes for a complaint
 */
router.get('/:id/images', async (req, res) => {
  try {
    const id = parseInt(req.params.id, 10);
    if (isNaN(id)) {
      return res.status(400).json({ success: false, message: 'Invalid complaint ID' });
    }

    const result = await db.query(
      `SELECT id, complaint_id, storage_path, file_name, file_size, mime_type, 
              sha256_hash, phash, created_at
       FROM complaint_images
       WHERE complaint_id = $1
       ORDER BY created_at ASC`,
      [id]
    );

    res.json({
      success: true,
      count: result.rows.length,
      images: result.rows,
    });
  } catch (err) {
    console.error('Error fetching complaint images:', err.message);
    res.status(500).json({ success: false, message: 'Internal server error' });
  }
});

/**
 * @route   GET /api/complaints/images/:imageId/verify
 * @desc    Verify cryptographic SHA-256 integrity of an image file on disk against database hash
 */
router.get('/images/:imageId/verify', async (req, res) => {
  try {
    const imageId = parseInt(req.params.imageId, 10);
    if (isNaN(imageId)) {
      return res.status(400).json({ success: false, message: 'Invalid image ID' });
    }

    const verification = await verifyImageIntegrity(imageId);
    res.json({
      success: true,
      verification,
    });
  } catch (err) {
    console.error('Error verifying image integrity:', err.message);
    const status = err.status || 500;
    res.status(status).json({ success: false, message: err.message });
  }
});

/**
 * @route   POST /api/complaints/images/check-duplicate
 * @desc    Check image for exact binary duplicate or visual perceptual duplicate before filing
 */
router.post('/images/check-duplicate', upload.single('image'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, message: 'Image file is required' });
    }

    const buffer = req.file.buffer || await fs.promises.readFile(req.file.path);
    const sha256 = computeSha256(buffer);
    const phash = await computePHash(buffer);

    const exactMatch = await db.query(
      `SELECT ci.id, ci.complaint_id, ci.storage_path, c.category, c.status, c.location
       FROM complaint_images ci
       JOIN complaints c ON ci.complaint_id = c.id
       WHERE ci.sha256_hash = $1
       ORDER BY ci.created_at ASC
       LIMIT 1`,
      [sha256]
    );

    const visualMatches = await findSimilarImages(phash, { threshold: 10, limit: 5 });

    // Clean up temporary upload if not associated with a complaint yet
    if (req.file.path && fs.existsSync(req.file.path)) {
      try { await fs.promises.unlink(req.file.path); } catch (_) {}
    }

    res.json({
      success: true,
      sha256,
      phash,
      isExactDuplicate: exactMatch.rows.length > 0,
      exactMatch: exactMatch.rows[0] || null,
      isVisualDuplicate: visualMatches.length > 0,
      visualMatches,
    });
  } catch (err) {
    console.error('Error checking duplicate image:', err.message);
    res.status(500).json({ success: false, message: 'Internal server error checking image' });
  }
});

module.exports = router;

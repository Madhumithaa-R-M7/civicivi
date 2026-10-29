const express = require('express');
const router = express.Router();
const db = require('../db');
const { authenticateToken } = require('../middleware/auth');

/**
 * @route   GET /api/rewards/stats
 * @desc    Get authenticated user's points and activity breakdown (strictly user-owned)
 */
router.get('/stats', authenticateToken, async (req, res) => {
  try {
    const userId = req.user.id;

    // Get user points from PostgreSQL
    const userRes = await db.query('SELECT points FROM users WHERE id = $1', [userId]);
    if (userRes.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'User not found' });
    }
    const currentPoints = userRes.rows[0].points || 0;

    // Get complaints breakdown for this user
    const complaintsRes = await db.query(
      'SELECT status, latitude, longitude, image_url FROM complaints WHERE user_id = $1',
      [userId]
    );

    let reported = complaintsRes.rows.length;
    let pending = 0;
    let inProgress = 0;
    let resolved = 0;
    let geoReports = 0;
    let photoReports = 0;

    for (const row of complaintsRes.rows) {
      if (row.status === 'Pending') pending++;
      else if (row.status === 'In Progress') inProgress++;
      else if (row.status === 'Resolved') resolved++;

      if (row.latitude != null && row.longitude != null) geoReports++;
      if (row.image_url && row.image_url.trim() !== '') photoReports++;
    }

    // Get points transaction history for this user
    const historyRes = await db.query(
      'SELECT * FROM points_log WHERE user_id = $1 ORDER BY created_at DESC LIMIT 20',
      [userId]
    );

    res.json({
      success: true,
      stats: {
        points: currentPoints,
        reported,
        pending,
        inProgress,
        resolved,
        geoReports,
        photoReports,
      },
      history: historyRes.rows,
    });
  } catch (err) {
    console.error('Error fetching rewards stats:', err.message);
    res.status(500).json({ success: false, message: 'Internal server error' });
  }
});

module.exports = router;

/**
 * CivicConnect Spatial Queries & Multi-Modal Priority Engine
 *
 * Algorithm 11: Haversine Distance Calculation
 *   - Accurate great-circle distance between GPS coordinates in meters.
 *
 * Algorithm 8: Weighted Priority Scoring
 *   - P = 0.25S + 0.20U + 0.15C + 0.15G + 0.10R + 0.15A (0 to 100 explainable score).
 *
 * Algorithm 9: Rule-Based Department Routing
 *   - Maps complaints to municipal departments based on category and civic jurisdiction.
 *
 * Algorithm 7: Spatiotemporal Similarity Duplicate Detection
 *   - Fuses geographic proximity, temporal window, text similarity, and image perceptual hashing.
 */

const db = require('../db');
const { computeTfIdf, cosineSimilarity } = require('./nlp_classifier');
const { hammingDistance } = require('./image_processing');

const EARTH_RADIUS_METERS = 6371000;

/**
 * Algorithm 11: Calculate great-circle distance between two GPS coordinates in meters.
 * @param {number} lat1
 * @param {number} lon1
 * @param {number} lat2
 * @param {number} lon2
 * @returns {number} Distance in meters
 */
function haversineDistance(lat1, lon1, lat2, lon2) {
  if (lat1 == null || lon1 == null || lat2 == null || lon2 == null) return Infinity;

  const toRad = deg => (deg * Math.PI) / 180;
  const phi1 = toRad(lat1);
  const phi2 = toRad(lat2);
  const deltaPhi = toRad(lat2 - lat1);
  const deltaLambda = toRad(lon2 - lon1);

  const a =
    Math.sin(deltaPhi / 2) * Math.sin(deltaPhi / 2) +
    Math.cos(phi1) * Math.cos(phi2) * Math.sin(deltaLambda / 2) * Math.sin(deltaLambda / 2);

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return Math.round(EARTH_RADIUS_METERS * c * 10) / 10;
}

/**
 * Algorithm 9: Rule-Based Department Routing
 * Resolves appropriate municipal department by category string.
 * @param {string} category
 * @returns {Object} { departmentName, departmentCode }
 */
function routeDepartment(category = '') {
  const cat = (category || '').toLowerCase();

  if (cat.includes('road') || cat.includes('traffic') || cat.includes('pothole')) {
    return { departmentName: 'Roads & Traffic', departmentCode: 'ROADS' };
  }
  if (cat.includes('clean') || cat.includes('waste') || cat.includes('garbage') || cat.includes('sanitation')) {
    return { departmentName: 'Cleanliness & Waste Management', departmentCode: 'SANITATION' };
  }
  if (cat.includes('water') || cat.includes('drain') || cat.includes('sewage') || cat.includes('leak')) {
    return { departmentName: 'Water Supply & Drainage', departmentCode: 'WATER' };
  }
  if (cat.includes('light') || cat.includes('lamp') || cat.includes('electric')) {
    return { departmentName: 'Street & Public Lighting', departmentCode: 'LIGHTING' };
  }
  return { departmentName: 'Public Infrastructure & Facilities', departmentCode: 'PUBLIC_WORKS' };
}

/**
 * Algorithm 8: Weighted Priority Scoring
 * Computes explainable priority score: P = 0.25S + 0.20U + 0.15C + 0.15G + 0.10R + 0.15A
 *
 * @param {Object} params
 * @param {string} [params.priority='Medium']
 * @param {string} [params.description='']
 * @param {string} [params.category='']
 * @param {number} [params.nearbyCount=0]
 * @param {Date|string} [params.createdAt]
 * @param {boolean} [params.hasGps=true]
 * @returns {Object} { score: number, breakdown: Object }
 */
function calculatePriorityScore({
  priority = 'Medium',
  description = '',
  category = '',
  nearbyCount = 0,
  createdAt = null,
  hasGps = true,
}) {
  // S: Severity (0 - 100)
  const normPriority = (priority || '').toLowerCase();
  let S = 50;
  if (normPriority.includes('emergency')) S = 100;
  else if (normPriority.includes('high')) S = 80;
  else if (normPriority.includes('low')) S = 25;

  // U: Urgency & Safety Risk (0 - 100)
  const desc = (description || '').toLowerCase();
  const dangerKeywords = [
    'hazard', 'danger', 'open manhole', 'spark', 'sparking', 'electric',
    'live wire', 'collapse', 'accident', 'fire', 'injury', 'deep crater', 'deep pothole',
    'flooding', 'burst pipe', 'electrocution', 'caved in'
  ];
  let U = 40;
  for (const kw of dangerKeywords) {
    if (desc.includes(kw)) {
      U = 95;
      break;
    }
  }
  if (U < 80 && (normPriority.includes('high') || normPriority.includes('emergency'))) {
    U = 75;
  }

  // C: Community Impact (0 - 100)
  const communityKeywords = [
    'school', 'hospital', 'station', 'railway', 'market', 'bus stop',
    'arterial', 'highway', 'main road', 'children', 'crowded', 'pedestrian'
  ];
  let C = 45;
  for (const kw of communityKeywords) {
    if (desc.includes(kw)) {
      C = 90;
      break;
    }
  }

  // G: Geographic Sensitivity (0 - 100)
  const G = hasGps ? 75 : 40;

  // R: Repeat Reports (0 - 100)
  const R = Math.min(100, Math.round(nearbyCount * 25));

  // A: Waiting Age (0 - 100)
  let A = 0;
  if (createdAt) {
    const elapsedDays = Math.max(0, (Date.now() - new Date(createdAt).getTime()) / (1000 * 60 * 60 * 24));
    A = Math.min(100, Math.round((elapsedDays / 7) * 100));
  }

  // Explainable weighted formula
  const P = Math.round(
    0.25 * S +
    0.20 * U +
    0.15 * C +
    0.15 * G +
    0.10 * R +
    0.15 * A
  );

  return {
    score: Math.max(0, Math.min(100, P)),
    breakdown: {
      severity: S,
      urgency: U,
      communityImpact: C,
      geographicSensitivity: G,
      repeatReports: R,
      waitingAge: A,
    },
  };
}

/**
 * Algorithm 7: Spatiotemporal Multi-Modal Duplicate Detection
 * Checks if a complaint is a duplicate based on location (Haversine), time window, category, text cosine similarity, and image pHash.
 *
 * @param {Object} params
 * @param {number} params.latitude
 * @param {number} params.longitude
 * @param {string} params.category
 * @param {string} params.description
 * @param {string} [params.phash=null]
 * @param {number} [params.radiusMeters=150]
 * @param {number} [params.daysWindow=30]
 * @param {number} [params.excludeComplaintId=null]
 * @returns {Promise<Object>} { isDuplicate, duplicateCandidates, topMatch, duplicateOfId, confidenceScore }
 */
async function checkSpatiotemporalDuplicate({
  latitude,
  longitude,
  category,
  description,
  phash = null,
  radiusMeters = 150,
  daysWindow = 30,
  excludeComplaintId = null,
}) {
  if (latitude == null || longitude == null) {
    return { isDuplicate: false, duplicateCandidates: [], topMatch: null, duplicateOfId: null, confidenceScore: 0 };
  }

  // Query recent complaints in the geographic bounding box (~0.005 deg is approx 550m)
  const latDelta = 0.005;
  const lngDelta = 0.005;

  let query = `
    SELECT c.id, c.category, c.description, c.priority, c.location, 
           c.latitude, c.longitude, c.status, c.created_at, c.image_url,
           ci.phash, ci.sha256_hash
    FROM complaints c
    LEFT JOIN complaint_images ci ON ci.complaint_id = c.id
    WHERE c.latitude BETWEEN $1 AND $2
      AND c.longitude BETWEEN $3 AND $4
      AND c.created_at >= (CURRENT_TIMESTAMP - ($5 || ' days')::INTERVAL)
      AND c.status NOT IN ('RESOLVED', 'CLOSED', 'REJECTED')
  `;
  const params = [
    latitude - latDelta,
    latitude + latDelta,
    longitude - lngDelta,
    longitude + lngDelta,
    daysWindow,
  ];

  if (excludeComplaintId) {
    params.push(excludeComplaintId);
    query += ` AND c.id != $${params.length}`;
  }

  query += ` ORDER BY c.created_at ASC LIMIT 100`;

  const result = await db.query(query, params);
  const candidates = [];
  const queryDesc = description || '';

  for (const row of result.rows) {
    // 1. Haversine distance
    const dist = haversineDistance(latitude, longitude, row.latitude, row.longitude);
    if (dist > radiusMeters) continue;

    // 2. Text Cosine Similarity
    const queryVec = computeTfIdf(queryDesc, [row.description || '']);
    const candVec = computeTfIdf(row.description || '', [queryDesc]);
    const textSimilarity = cosineSimilarity(queryVec, candVec);

    // 3. Image pHash Hamming Distance
    let imageSimilarity = null;
    let distHamming = null;
    if (phash && row.phash) {
      distHamming = hammingDistance(phash, row.phash);
      imageSimilarity = Math.max(0, 1.0 - (distHamming / 20.0));
    }

    // 4. Category match
    const categoryMatch = row.category && category && (
      row.category.toLowerCase().split(' ')[0] === category.toLowerCase().split(' ')[0]
    );

    // Multi-modal fused score (0.0 to 1.0)
    // Distance weight: 0.35, Text weight: 0.35, Category: 0.15, Image: 0.15
    const distanceScore = Math.max(0, 1.0 - (dist / radiusMeters));
    let fusedScore = (0.40 * distanceScore) + (0.40 * textSimilarity) + (categoryMatch ? 0.20 : 0.0);

    if (imageSimilarity != null) {
      fusedScore = (0.30 * distanceScore) + (0.30 * textSimilarity) + (0.25 * imageSimilarity) + (categoryMatch ? 0.15 : 0.0);
    }

    // Flag as duplicate if fusedScore >= 0.55 OR (image exact match && dist <= radiusMeters)
    const isCandidateDuplicate = fusedScore >= 0.55 || (distHamming != null && distHamming <= 8);

    if (isCandidateDuplicate || textSimilarity >= 0.50 || dist <= 50) {
      candidates.push({
        complaintId: row.id,
        category: row.category,
        description: row.description,
        distanceMeters: dist,
        textSimilarity,
        hammingDistance: distHamming,
        imageSimilarity,
        categoryMatch,
        fusedScore: parseFloat(fusedScore.toFixed(3)),
        status: row.status,
        createdAt: row.created_at,
      });
    }
  }

  // Sort by highest fused score
  candidates.sort((a, b) => b.fusedScore - a.fusedScore);
  const topMatch = candidates[0] || null;
  const isDuplicate = topMatch != null && topMatch.fusedScore >= 0.55;

  return {
    isDuplicate,
    confidenceScore: topMatch ? Math.round(topMatch.fusedScore * 100) : 0,
    duplicateOfId: isDuplicate ? topMatch.complaintId : null,
    topMatch,
    duplicateCandidates: candidates.slice(0, 5),
  };
}

module.exports = {
  haversineDistance,
  routeDepartment,
  calculatePriorityScore,
  checkSpatiotemporalDuplicate,
};

/**
 * CivicConnect Image Processing & Integrity Engine (Algorithms 5 & 6)
 *
 * Algorithm 5: SHA-256 Cryptographic Image Hashing
 *   - Verifies raw file integrity.
 *   - Detects exact binary duplicates across uploaded complaint evidence.
 *
 * Algorithm 6: Perceptual Hashing (pHash) & 64-Bit Hamming Distance
 *   - Resizes image to 32x32, converts to grayscale, computes 2D Discrete Cosine Transform (DCT).
 *   - Extracts top-left 8x8 low-frequency components representing visual structure.
 *   - Thresholds against median to produce 64-bit fingerprint (16-char hex).
 *   - Computes bitwise Hamming distance to detect visual near-duplicates regardless of
 *     compression, resizing, or minor artifacts.
 */

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const sharp = require('sharp');
const db = require('../db');

// Precomputed 2D Discrete Cosine Transform (DCT-II) matrix for N = 32
const N = 32;
const C = [];
for (let u = 0; u < N; u++) {
  C[u] = [];
  const alpha = u === 0 ? 1 / Math.sqrt(N) : Math.sqrt(2 / N);
  for (let x = 0; x < N; x++) {
    C[u][x] = alpha * Math.cos(((2 * x + 1) * u * Math.PI) / (2 * N));
  }
}

/**
 * Perform 2D-DCT on 32x32 matrix and extract top-left 8x8 low frequencies.
 * @param {Float64Array} matrix 32x32 = 1024 grayscale pixel values
 * @returns {Float64Array} 8x8 = 64 low frequency DCT coefficients
 */
function computeDct8x8(matrix) {
  // Step 1: 1D DCT across rows
  const intermediate = new Float64Array(32 * 32);
  for (let y = 0; y < 32; y++) {
    const rowOffset = y * 32;
    for (let u = 0; u < 32; u++) {
      let sum = 0;
      for (let x = 0; x < 32; x++) {
        sum += C[u][x] * matrix[rowOffset + x];
      }
      intermediate[u + y * 32] = sum;
    }
  }

  // Step 2: 1D DCT down columns for low frequencies (u < 8, v < 8)
  const dct8x8 = new Float64Array(64);
  for (let u = 0; u < 8; u++) {
    for (let v = 0; v < 8; v++) {
      let sum = 0;
      for (let y = 0; y < 32; y++) {
        sum += C[v][y] * intermediate[u + y * 32];
      }
      dct8x8[v * 8 + u] = sum;
    }
  }
  return dct8x8;
}

/**
 * Algorithm 5: Compute SHA-256 cryptographic digest of image buffer or file.
 * @param {Buffer|string} input - Buffer or file path string
 * @returns {string} 64-character lowercase hex string
 */
function computeSha256(input) {
  let buffer;
  if (Buffer.isBuffer(input)) {
    buffer = input;
  } else if (typeof input === 'string') {
    buffer = fs.readFileSync(input);
  } else {
    throw new Error('computeSha256 requires a Buffer or string file path');
  }
  return crypto.createHash('sha256').update(buffer).digest('hex');
}

/**
 * Algorithm 6: Compute 64-bit Perceptual Hash (pHash) using 2D DCT.
 * @param {Buffer|string} input - Buffer or file path string
 * @returns {Promise<string>} 16-character hexadecimal string (64 bits)
 */
async function computePHash(input) {
  let buffer;
  if (Buffer.isBuffer(input)) {
    buffer = input;
  } else if (typeof input === 'string') {
    buffer = await fs.promises.readFile(input);
  } else {
    throw new Error('computePHash requires a Buffer or string file path');
  }

  // 1. Resize to 32x32, 2. Convert to grayscale raw 8-bit bytes
  const rawData = await sharp(buffer)
    .resize(32, 32, { fit: 'fill' })
    .grayscale()
    .raw()
    .toBuffer();

  const matrix = new Float64Array(32 * 32);
  for (let i = 0; i < rawData.length; i++) {
    matrix[i] = rawData[i];
  }

  // 3. Compute 2D DCT & extract 8x8 low frequencies
  const dct = computeDct8x8(matrix);

  // 4. Compute median of AC frequencies (exclude DC component at index 0)
  const acValues = Array.from(dct.slice(1)).sort((a, b) => a - b);
  const median = acValues[Math.floor(acValues.length / 2)];

  // 5. Construct 64-bit hash (1 if coefficient > median, else 0)
  let hex = '';
  for (let byteIdx = 0; byteIdx < 8; byteIdx++) {
    let byteVal = 0;
    for (let bitIdx = 0; bitIdx < 8; bitIdx++) {
      const idx = byteIdx * 8 + bitIdx;
      if (dct[idx] > median) {
        byteVal |= (1 << (7 - bitIdx));
      }
    }
    hex += byteVal.toString(16).padStart(2, '0');
  }
  return hex;
}

/**
 * Compute bitwise Hamming Distance between two 16-char hex perceptual hashes.
 * @param {string} hex1 - First 64-bit hex hash
 * @param {string} hex2 - Second 64-bit hex hash
 * @returns {number} Distance between 0 and 64 (0 = identical)
 */
function hammingDistance(hex1, hex2) {
  if (!hex1 || !hex2 || hex1.length !== hex2.length) return 64;
  try {
    const b1 = BigInt('0x' + hex1);
    const b2 = BigInt('0x' + hex2);
    let xor = b1 ^ b2;
    let dist = 0;
    while (xor > 0n) {
      dist += Number(xor & 1n);
      xor >>= 1n;
    }
    return dist;
  } catch (_) {
    return 64;
  }
}

/**
 * Scan database for similar images using pHash Hamming distance
 * @param {string} targetPhash - 16-char hex pHash to compare against
 * @param {Object} [options]
 * @param {number} [options.threshold=10] - Max Hamming distance for similarity
 * @param {number} [options.excludeComplaintId=null] - Exclude images from this complaint
 * @param {number} [options.limit=10]
 * @returns {Promise<Array>} List of matching image records with distance
 */
async function findSimilarImages(targetPhash, options = {}) {
  const { threshold = 10, excludeComplaintId = null, limit = 10 } = options;

  let query = `
    SELECT ci.id, ci.complaint_id, ci.storage_path, ci.file_name, 
           ci.sha256_hash, ci.phash, ci.created_at,
           c.category, c.status, c.location, c.latitude, c.longitude
    FROM complaint_images ci
    JOIN complaints c ON ci.complaint_id = c.id
    WHERE ci.phash IS NOT NULL
  `;
  const params = [];

  if (excludeComplaintId) {
    params.push(excludeComplaintId);
    query += ` AND ci.complaint_id != $${params.length}`;
  }

  query += ` ORDER BY ci.created_at ASC LIMIT 500`;

  const result = await db.query(query, params);
  const matches = [];

  for (const row of result.rows) {
    const dist = hammingDistance(targetPhash, row.phash);
    if (dist <= threshold) {
      matches.push({
        ...row,
        hamming_distance: dist,
        similarity_score: Math.max(0, 100 - Math.round((dist / 64) * 100)),
      });
    }
  }

  // Sort by closest visual match (lowest Hamming distance)
  matches.sort((a, b) => a.hamming_distance - b.hamming_distance);
  return matches.slice(0, limit);
}

/**
 * Check if a SHA-256 hash already exists in the database
 * @param {string} sha256 - 64-char hex SHA-256 hash
 * @param {number} [excludeComplaintId=null]
 * @returns {Promise<Object|null>} Matching image record if found
 */
async function findExactDuplicateImage(sha256, excludeComplaintId = null) {
  let query = `
    SELECT ci.id, ci.complaint_id, ci.storage_path, ci.file_name, ci.sha256_hash, ci.phash,
           c.category, c.status, c.location
    FROM complaint_images ci
    JOIN complaints c ON ci.complaint_id = c.id
    WHERE ci.sha256_hash = $1
  `;
  const params = [sha256];

  if (excludeComplaintId) {
    params.push(excludeComplaintId);
    query += ` AND ci.complaint_id != $2`;
  }

  query += ` ORDER BY ci.created_at ASC LIMIT 1`;
  const result = await db.query(query, params);
  return result.rows.length > 0 ? result.rows[0] : null;
}

/**
 * Process and persist an uploaded complaint image file
 * Computes SHA-256, pHash, checks for duplicates, and records in complaint_images.
 *
 * @param {Object} params
 * @param {number} params.complaintId
 * @param {Object} params.file - Multer file object or { buffer, path, originalname, mimetype, size }
 * @param {string} [params.storagePath]
 * @returns {Promise<Object>} Analysis result with hashes and duplicate flags
 */
async function processAndStoreImage({ complaintId, file, storagePath }) {
  let buffer;
  let filePath;

  if (file.buffer) {
    buffer = file.buffer;
    filePath = storagePath || file.path;
  } else if (file.path) {
    filePath = file.path;
    buffer = await fs.promises.readFile(file.path);
  } else {
    throw new Error('Invalid file object provided to processAndStoreImage');
  }

  const fileName = file.filename || file.originalname || path.basename(filePath || 'unknown.jpg');
  const fileSize = file.size || buffer.length;
  const mimeType = file.mimetype || 'image/jpeg';
  const finalStoragePath = storagePath || (filePath ? `/uploads/${path.basename(filePath)}` : `/uploads/${fileName}`);

  // 1. Compute SHA-256 (Algorithm 5)
  const sha256 = computeSha256(buffer);

  // 2. Compute pHash (Algorithm 6)
  let phash = null;
  try {
    phash = await computePHash(buffer);
  } catch (phashErr) {
    console.warn(`[IMAGE_PROCESSING] Failed to compute pHash for ${fileName}:`, phashErr.message);
  }

  // 3. Exact binary duplicate check (Algorithm 5)
  const exactMatch = await findExactDuplicateImage(sha256, complaintId);

  // 4. Perceptual near-duplicate check (Algorithm 6)
  let visualMatches = [];
  if (phash) {
    visualMatches = await findSimilarImages(phash, {
      threshold: 10,
      excludeComplaintId: complaintId,
      limit: 5,
    });
  }

  const isExactDuplicate = exactMatch != null;
  const isVisualDuplicate = visualMatches.length > 0;
  const bestVisualMatch = visualMatches[0] || null;

  // 5. Store image record in complaint_images table
  const insertRes = await db.query(
    `INSERT INTO complaint_images 
     (complaint_id, storage_path, file_name, file_size, mime_type, sha256_hash, phash)
     VALUES ($1, $2, $3, $4, $5, $6, $7)
     RETURNING *`,
    [complaintId, finalStoragePath, fileName, fileSize, mimeType, sha256, phash]
  );
  const imageRecord = insertRes.rows[0];

  // 6. Update complaint duplicate metadata if duplicate detected
  if (isExactDuplicate || isVisualDuplicate) {
    const duplicateOfId = exactMatch ? exactMatch.complaint_id : bestVisualMatch.complaint_id;
    const duplicateScore = isExactDuplicate ? 1.0 : (bestVisualMatch.similarity_score / 100);

    await db.query(
      `UPDATE complaints
       SET duplicate_of_id = COALESCE(duplicate_of_id, $1),
           duplicate_score = GREATEST(COALESCE(duplicate_score, 0), $2),
           updated_at = CURRENT_TIMESTAMP
       WHERE id = $3`,
      [duplicateOfId, duplicateScore, complaintId]
    );
  }

  return {
    imageRecord,
    sha256,
    phash,
    isExactDuplicate,
    exactMatch,
    isVisualDuplicate,
    bestVisualMatch,
    duplicateOfId: exactMatch ? exactMatch.complaint_id : (bestVisualMatch ? bestVisualMatch.complaint_id : null),
    hammingDistance: bestVisualMatch ? bestVisualMatch.hamming_distance : null,
    similarityScore: bestVisualMatch ? bestVisualMatch.similarity_score : (isExactDuplicate ? 100 : 0),
  };
}

/**
 * Verify cryptographic SHA-256 integrity of a stored image against disk
 * @param {number} imageId - ID in complaint_images table
 * @returns {Promise<Object>} Integrity check result
 */
async function verifyImageIntegrity(imageId) {
  const result = await db.query('SELECT * FROM complaint_images WHERE id = $1', [imageId]);
  if (result.rows.length === 0) {
    const err = new Error('Image record not found');
    err.status = 404;
    throw err;
  }

  const img = result.rows[0];
  const uploadsDir = path.join(__dirname, '..', 'uploads');
  const diskPath = path.join(uploadsDir, path.basename(img.storage_path));

  if (!fs.existsSync(diskPath)) {
    return {
      valid: false,
      reason: 'Image file does not exist on disk',
      storedHash: img.sha256_hash,
      currentHash: null,
    };
  }

  const diskBuffer = await fs.promises.readFile(diskPath);
  const currentHash = computeSha256(diskBuffer);
  const valid = currentHash === img.sha256_hash;

  return {
    valid,
    storedHash: img.sha256_hash,
    currentHash,
    fileName: img.file_name,
    storagePath: img.storage_path,
    checkedAt: new Date().toISOString(),
  };
}

module.exports = {
  computeSha256,
  computePHash,
  hammingDistance,
  findSimilarImages,
  findExactDuplicateImage,
  processAndStoreImage,
  verifyImageIntegrity,
};

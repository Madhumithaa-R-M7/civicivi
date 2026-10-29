const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
require('dotenv').config();
const db = require('./db');

const BASE_URL = 'http://localhost:5000';

async function runTests() {
  console.log('====================================================');
  console.log('🚀 Running CivicConnect Complaint & Image Upload Tests');
  console.log('====================================================\n');

  // 1. Get an existing user or create one
  let userRes = await db.query('SELECT id, name, email, role FROM users WHERE role = $1 LIMIT 1', ['user']);
  let user = userRes.rows[0];
  if (!user) {
    const insertRes = await db.query(
      `INSERT INTO users (name, email, role, location, points, is_verified) 
       VALUES ('Test Citizen', 'test_citizen@example.com', 'user', 'Mumbai', 10, true) 
       RETURNING *`
    );
    user = insertRes.rows[0];
  }

  console.log(`👤 Using test user: ID=${user.id}, Name="${user.name}", Role="${user.role}"`);

  // Generate valid JWT token
  const token = jwt.sign(
    { id: user.id, role: user.role, name: user.name, jti: crypto.randomBytes(16).toString('hex') },
    process.env.JWT_SECRET || 'civicconnect_super_secret_jwt_key_2026',
    { expiresIn: '1h' }
  );

  // Create test dummy files
  const testJpgPath = path.join(__dirname, 'test_sample.jpg');
  const testPngPath = path.join(__dirname, 'test_sample.png');
  const testTxtPath = path.join(__dirname, 'test_invalid.txt');

  // 1x1 valid JPEG bytes
  const dummyJpgBytes = Buffer.from([
    0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x01, 0x00, 0x48,
    0x00, 0x48, 0x00, 0x00, 0xff, 0xdb, 0x00, 0x43, 0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08,
    0x07, 0x07, 0x07, 0x09, 0x09, 0x08, 0x0a, 0x0c, 0x14, 0x0d, 0x0c, 0x0b, 0x0b, 0x0c, 0x19, 0x12,
    0x13, 0x0f, 0x14, 0x1d, 0x1a, 0x1f, 0x1e, 0x1d, 0x1a, 0x1c, 0x1c, 0x20, 0x24, 0x2e, 0x27, 0x20,
    0x22, 0x2c, 0x23, 0x1c, 0x1c, 0x28, 0x37, 0x29, 0x2c, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1f, 0x27,
    0x39, 0x3d, 0x38, 0x32, 0x3c, 0x2e, 0x33, 0x34, 0x32, 0xff, 0xc0, 0x00, 0x0b, 0x08, 0x00, 0x01,
    0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xff, 0xc4, 0x00, 0x1f, 0x00, 0x00, 0x01, 0x05, 0x01, 0x01,
    0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04,
    0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0xff, 0xda, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3f,
    0x00, 0x7f, 0x00, 0xff, 0xd9
  ]);
  fs.writeFileSync(testJpgPath, dummyJpgBytes);

  // 1x1 valid PNG bytes
  const dummyPngBytes = Buffer.from([
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4,
    0x89, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0x60, 0x60, 0x60, 0x00,
    0x00, 0x00, 0x04, 0x00, 0x01, 0x27, 0x34, 0x27, 0x0a, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e,
    0x44, 0xae, 0x42, 0x60, 0x82
  ]);
  fs.writeFileSync(testPngPath, dummyPngBytes);

  fs.writeFileSync(testTxtPath, 'This is a text file, not an image!');

  let passedTests = 0;
  let totalTests = 0;

  // TEST 1: Submit complaint with valid JPEG photo and full GPS metadata
  totalTests++;
  console.log('--- TEST 1: Submit complaint with valid JPEG image & full GPS metadata ---');
  try {
    const formData = new FormData();
    formData.append('category', 'Roads & Traffic');
    formData.append('description', 'Severe pothole on Main Street causing vehicular damage');
    formData.append('priority', 'High Priority');
    formData.append('location', '42 Linking Road, Bandra West, Mumbai, Maharashtra 400050');
    formData.append('latitude', '19.059600');
    formData.append('longitude', '72.829500');
    formData.append('locationAccuracy', '4.2');
    formData.append('locationCapturedAt', new Date().toISOString());

    const fileBlob = new Blob([fs.readFileSync(testJpgPath)], { type: 'image/jpeg' });
    formData.append('image', fileBlob, 'camera_photo.jpg');

    const res = await fetch(`${BASE_URL}/api/complaints`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
      },
      body: formData,
    });

    const data = await res.json();
    console.log(`Status Code: ${res.status}`);
    console.log('Response body:', JSON.stringify(data, null, 2));

    if (res.status === 201 && data.success === true && data.complaint && data.complaint.id) {
      console.log('✅ TEST 1 PASSED: Complaint created successfully with ID:', data.complaint.id);

      // Verify in PostgreSQL database
      const dbCheck = await db.query('SELECT * FROM complaints WHERE id = $1', [data.complaint.id]);
      if (dbCheck.rows.length > 0) {
        const row = dbCheck.rows[0];
        console.log('✅ DB Record Verified:');
        console.log(`   - ID: ${row.id}`);
        console.log(`   - Category: ${row.category}`);
        console.log(`   - Location: ${row.location}`);
        console.log(`   - Latitude: ${row.latitude}, Longitude: ${row.longitude}`);
        console.log(`   - Accuracy: ${row.location_accuracy} m`);
        console.log(`   - Captured At: ${row.location_captured_at}`);
        console.log(`   - Image URL: ${row.image_url}`);
        console.log(`   - Status: ${row.status}`);
        console.log(`   - Priority Score: ${row.priority_score}`);
        passedTests++;
      } else {
        console.error('❌ TEST 1 FAILED: DB record not found');
      }
    } else {
      console.error('❌ TEST 1 FAILED:', data);
    }
  } catch (err) {
    console.error('❌ TEST 1 EXCEPTION:', err);
  }

  // TEST 2: Submit complaint with valid PNG photo
  totalTests++;
  console.log('\n--- TEST 2: Submit complaint with valid PNG image ---');
  try {
    const formData = new FormData();
    formData.append('category', 'Cleanliness & Waste Management');
    formData.append('description', 'Garbage dumping near municipal playground');
    formData.append('priority', 'Medium Priority');
    formData.append('location', 'Plot 15, Shivaji Park, Dadar, Mumbai, Maharashtra 400028');
    formData.append('latitude', '19.026900');
    formData.append('longitude', '72.837400');
    formData.append('locationAccuracy', '6.8');
    formData.append('locationCapturedAt', new Date().toISOString());

    const fileBlob = new Blob([fs.readFileSync(testPngPath)], { type: 'image/png' });
    formData.append('image', fileBlob, 'captured_issue.png');

    const res = await fetch(`${BASE_URL}/api/complaints`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
      },
      body: formData,
    });

    const data = await res.json();
    console.log(`Status Code: ${res.status}`);
    console.log('Response body:', JSON.stringify(data, null, 2));

    if (res.status === 201 && data.success === true && data.complaint && data.complaint.id) {
      console.log('✅ TEST 2 PASSED: PNG image complaint created with ID:', data.complaint.id);
      passedTests++;
    } else {
      console.error('❌ TEST 2 FAILED:', data);
    }
  } catch (err) {
    console.error('❌ TEST 2 EXCEPTION:', err);
  }

  // TEST 3: Submit invalid file type (non-image .txt) -> Should return 400 with exact error message
  totalTests++;
  console.log('\n--- TEST 3: Submit invalid file type (.txt) -> Expect validation error ---');
  try {
    const formData = new FormData();
    formData.append('category', 'Roads & Traffic');
    formData.append('description', 'Testing rejection of invalid non-image file attachment');
    formData.append('priority', 'Low Priority');
    formData.append('location', 'Marine Drive, Mumbai');
    formData.append('latitude', '18.943800');
    formData.append('longitude', '72.823400');

    const fileBlob = new Blob([fs.readFileSync(testTxtPath)], { type: 'text/plain' });
    formData.append('image', fileBlob, 'document.txt');

    const res = await fetch(`${BASE_URL}/api/complaints`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
      },
      body: formData,
    });

    const data = await res.json();
    console.log(`Status Code: ${res.status}`);
    console.log('Response body:', JSON.stringify(data, null, 2));

    if (res.status === 400 && data.message && data.message.includes('Only image files (JPEG, PNG, WEBP) are allowed.')) {
      console.log('✅ TEST 3 PASSED: Server rejected non-image file with correct message:', data.message);
      passedTests++;
    } else {
      console.error('❌ TEST 3 FAILED: Server did not return expected 400 with image validation error');
    }
  } catch (err) {
    console.error('❌ TEST 3 EXCEPTION:', err);
  }

  // TEST 4: Submit complaint without description -> Expect 400 "Description is required"
  totalTests++;
  console.log('\n--- TEST 4: Submit complaint without description -> Expect validation error ---');
  try {
    const formData = new FormData();
    formData.append('category', 'Roads & Traffic');
    formData.append('description', '');
    formData.append('priority', 'Medium Priority');
    formData.append('location', 'Marine Drive, Mumbai');

    const res = await fetch(`${BASE_URL}/api/complaints`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
      },
      body: formData,
    });

    const data = await res.json();
    console.log(`Status Code: ${res.status}`);
    console.log('Response body:', JSON.stringify(data, null, 2));

    if (res.status === 400 && data.message === 'Description is required') {
      console.log('✅ TEST 4 PASSED: Missing required description correctly rejected');
      passedTests++;
    } else {
      console.error('❌ TEST 4 FAILED: Expected 400 with "Description is required"');
    }
  } catch (err) {
    console.error('❌ TEST 4 EXCEPTION:', err);
  }

  // Clean up test files
  try {
    if (fs.existsSync(testJpgPath)) fs.unlinkSync(testJpgPath);
    if (fs.existsSync(testPngPath)) fs.unlinkSync(testPngPath);
    if (fs.existsSync(testTxtPath)) fs.unlinkSync(testTxtPath);
  } catch (_) {}

  console.log('\n====================================================');
  console.log(`📊 Test Summary: ${passedTests}/${totalTests} tests passed`);
  console.log('====================================================');

  process.exit(passedTests === totalTests ? 0 : 1);
}

runTests().catch(err => {
  console.error('Fatal test error:', err);
  process.exit(1);
});

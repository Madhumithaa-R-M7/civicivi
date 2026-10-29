const http = require('http');
const db = require('./db');
const bcrypt = require('bcrypt');
const fs = require('fs');
const path = require('path');
const sharp = require('sharp');

const PORT = 5000;
const BASE = `http://localhost:${PORT}`;

function request(urlPath, method, body, headers = {}) {
  return new Promise((resolve, reject) => {
    const url = new URL(urlPath, BASE);
    const options = {
      hostname: url.hostname,
      port: url.port,
      path: url.pathname + url.search,
      method: method,
      headers: {
        'Content-Type': 'application/json',
        ...headers,
      },
    };

    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          const parsed = JSON.parse(data);
          resolve({ status: res.statusCode, headers: res.headers, body: parsed });
        } catch (_) {
          resolve({ status: res.statusCode, headers: res.headers, raw: data });
        }
      });
    });

    req.on('error', reject);
    if (body) {
      req.write(typeof body === 'string' ? body : JSON.stringify(body));
    }
    req.end();
  });
}

function multipartRequest(urlPath, fields, fileField, headers = {}) {
  return new Promise((resolve, reject) => {
    const boundary = '--------------------------' + Date.now().toString(16);
    const url = new URL(urlPath, BASE);

    const buffers = [];

    // Append fields
    for (const [key, value] of Object.entries(fields)) {
      if (value != null) {
        buffers.push(Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="${key}"\r\n\r\n${value}\r\n`));
      }
    }

    // Append file if present
    if (fileField && fileField.buffer) {
      buffers.push(Buffer.from(
        `--${boundary}\r\nContent-Disposition: form-data; name="${fileField.name}"; filename="${fileField.filename}"\r\nContent-Type: ${fileField.contentType || 'image/jpeg'}\r\n\r\n`
      ));
      buffers.push(fileField.buffer);
      buffers.push(Buffer.from('\r\n'));
    }

    buffers.push(Buffer.from(`--${boundary}--\r\n`));
    const fullBody = Buffer.concat(buffers);

    const options = {
      hostname: url.hostname,
      port: url.port,
      path: url.pathname + url.search,
      method: 'POST',
      headers: {
        'Content-Type': `multipart/form-data; boundary=${boundary}`,
        'Content-Length': fullBody.length,
        ...headers,
      },
    };

    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          const parsed = JSON.parse(data);
          resolve({ status: res.statusCode, body: parsed });
        } catch (_) {
          resolve({ status: res.statusCode, raw: data });
        }
      });
    });

    req.on('error', reject);
    req.write(fullBody);
    req.end();
  });
}

async function runTests() {
  console.log('======================================================================');
  console.log('🧪 CivicConnect End-to-End Authentication & GPS Camera Integration Tests');
  console.log('======================================================================\n');

  let passed = 0;
  let failed = 0;

  function report(num, name, condition, details = '') {
    if (condition) {
      console.log(`Test ${num.toString().padStart(2, '0')}: [PASSED] ✅ ${name} ${details}`);
      passed++;
    } else {
      console.error(`Test ${num.toString().padStart(2, '0')}: [FAILED] ❌ ${name} ${details}`);
      failed++;
    }
  }

  try {
    // Clean up test data from prior test executions to ensure clean, deterministic assertions
    try {
      await db.query(`
        DELETE FROM otp_challenges WHERE email = 'sec23cj025@sairamtap.edu.in';
        DELETE FROM complaint_assignments WHERE staff_id IN (SELECT id FROM users WHERE email LIKE '%@example.com' OR phone LIKE '+9198%');
        DELETE FROM complaints WHERE user_id IN (SELECT id FROM users WHERE email LIKE '%@example.com' OR phone LIKE '+9198%') OR description LIKE '%pothole%' OR description LIKE '%Duplicate report%' OR description LIKE '%Broken streetlight%';
        DELETE FROM users WHERE email LIKE '%@example.com' OR phone LIKE '+9198%';
      `);
    } catch (cleanupErr) {
      console.warn('Initial cleanup note:', cleanupErr.message);
    }

    // -------------------------------------------------------------
    // PART 1: AUTHENTICATION VERIFICATION
    // -------------------------------------------------------------
    console.log('--- PART 1: AUTHENTICATION & SECURITY VERIFICATION ---');

    // 1. Health check
    const health = await request('/api/health', 'GET');
    report(1, 'Health Check Endpoint', health.status === 200 && health.body.status === 'ok');

    // 2. Register Citizen 1 with Email + Password
    const uid = Date.now();
    const citizenEmail = `citizen_${uid}@example.com`;
    const citizenPassword = 'SecurePassword@123';
    const regEmail = await request('/api/auth/register', 'POST', {
      name: 'Lokesh Citizen',
      email: citizenEmail,
      password: citizenPassword,
    });
    report(2, 'Register Citizen with Email + Password', regEmail.status === 201 && regEmail.body.token != null);
    const tokenCitizen1 = regEmail.body.token;
    const userCitizen1Id = regEmail.body.user.id;

    // 3. Register Citizen 2 with Mobile Phone + Password
    const citizenPhone = `+9198${Math.floor(10000000 + Math.random() * 90000000)}`;
    const regPhone = await request('/api/auth/register', 'POST', {
      name: 'Rohan Sharma',
      phone: citizenPhone,
      password: 'PhonePassword@123',
    });
    report(3, 'Register Citizen with Mobile Phone + Password', regPhone.status === 201 && regPhone.body.token != null);
    const tokenCitizen2 = regPhone.body.token;
    const userCitizen2Id = regPhone.body.user.id;

    // 4. Reject duplicate email
    const dupEmail = await request('/api/auth/register', 'POST', {
      name: 'Another User',
      email: citizenEmail,
      password: 'AnotherPassword@123',
    });
    report(4, 'Reject Duplicate Email Registration (HTTP 409)', dupEmail.status === 409 && dupEmail.body.success === false);

    // 5. Reject duplicate phone
    const dupPhone = await request('/api/auth/register', 'POST', {
      name: 'Another User',
      phone: citizenPhone,
      password: 'AnotherPassword@123',
    });
    report(5, 'Reject Duplicate Phone Registration (HTTP 409)', dupPhone.status === 409 && dupPhone.body.success === false);

    // 6. Verify passwords hashed with bcrypt in PostgreSQL (Never plain-text)
    const dbUser1 = await db.query('SELECT password_hash FROM users WHERE id = $1', [userCitizen1Id]);
    const isBcrypt = dbUser1.rows[0].password_hash.startsWith('$2b$');
    const matchesPassword = await bcrypt.compare(citizenPassword, dbUser1.rows[0].password_hash);
    report(6, 'Passwords Hashed with bcrypt in PostgreSQL (No plaintext stored)', isBcrypt && matchesPassword);

    // 7. Login with Email + Password
    const loginEmail = await request('/api/auth/login', 'POST', {
      identifier: citizenEmail,
      password: citizenPassword,
    });
    report(7, 'Login with Registered Email + Password', loginEmail.status === 200 && loginEmail.body.token != null);

    // 8. Login with Phone + Password
    const loginPhone = await request('/api/auth/login', 'POST', {
      identifier: citizenPhone,
      password: 'PhonePassword@123',
    });
    report(8, 'Login with Registered Mobile Phone + Password', loginPhone.status === 200 && loginPhone.body.token != null);

    // 9. Login with Incorrect Password
    const loginBadPass = await request('/api/auth/login', 'POST', {
      identifier: citizenEmail,
      password: 'WrongPassword999!',
    });
    report(9, 'Reject Login with Incorrect Password (HTTP 401 Generic Error)', loginBadPass.status === 401 && loginBadPass.body.message === 'Invalid email or password.');

    // 10. Resend Email Password Recovery Verification
    const recoveryEmail = 'sec23cj025@sairamtap.edu.in';
    const initialResetPass = 'InitPassword@123';
    const initHash = await bcrypt.hash(initialResetPass, 10);
    await db.query(`
      INSERT INTO users (name, email, password_hash, role, location, points, is_verified)
      VALUES ('Verified Reset Citizen', $1, $2, 'user', 'Chennai', 20, TRUE)
      ON CONFLICT (email) DO UPDATE SET password_hash = $2
    `, [recoveryEmail, initHash]);

    const forgotRes = await request('/api/auth/forgot-password', 'POST', { email: recoveryEmail });
    report(10, 'Forgot Password Request (Resend Live Email OTP Delivered)', forgotRes.status === 200 && forgotRes.body.success === true);
    const resetVid = forgotRes.body.verificationId;

    // 11. Verify OTP Hash Stored in PostgreSQL with purpose 'password_reset'
    const dbResetChallenge = await db.query('SELECT * FROM otp_challenges WHERE verification_id = $1', [resetVid]);
    report(
      11,
      'Password Reset OTP Stored as bcrypt Hash in PostgreSQL',
      dbResetChallenge.rows.length > 0 &&
      dbResetChallenge.rows[0].otp_hash.startsWith('$2b$') &&
      dbResetChallenge.rows[0].purpose === 'password_reset'
    );

    // 12. Complete Password Reset & Authenticate with New Password
    const testVid = 'reset_test_token_' + Date.now();
    const testOtp = '789123';
    const testOtpHash = await bcrypt.hash(testOtp, 10);
    await db.query(`
      INSERT INTO otp_challenges (verification_id, email, otp_hash, purpose, attempts, max_attempts, is_consumed, expires_at)
      VALUES ($1, $2, $3, 'password_reset', 0, 5, FALSE, CURRENT_TIMESTAMP + INTERVAL '10 minutes')
    `, [testVid, recoveryEmail, testOtpHash]);

    const verifyReset = await request('/api/auth/verify-reset-otp', 'POST', {
      verificationId: testVid,
      otp: testOtp,
    });
    report(12, 'Verify Password Reset OTP & Issue 15-min Reset Token', verifyReset.status === 200 && verifyReset.body.resetToken != null);
    const resetToken = verifyReset.body.resetToken;

    const brandNewPass = 'BrandNewPassword@999';
    const resetPassRes = await request('/api/auth/reset-password', 'POST', {
      resetToken,
      newPassword: brandNewPass,
    });
    report(13, 'Save New Password Hash in PostgreSQL via reset-password', resetPassRes.status === 200 && resetPassRes.body.success === true);

    const loginWithNewPass = await request('/api/auth/login', 'POST', {
      identifier: recoveryEmail,
      password: brandNewPass,
    });
    report(14, 'Login Successfully with New Password after Reset', loginWithNewPass.status === 200 && loginWithNewPass.body.token != null);

    // -------------------------------------------------------------
    // PART 2: GPS-ENABLED CAMERA & COMPLAINT SUBMISSION
    // -------------------------------------------------------------
    console.log('\n--- PART 2: GPS-ENABLED CAMERA & COMPLAINTS VERIFICATION ---');

    // 15. Reject Unauthenticated Complaint Submission (HTTP 401)
    const unauthComplaint = await request('/api/complaints', 'POST', {
      category: 'Roads & Traffic',
      description: 'Pothole on main road',
    });
    report(15, 'Reject Unauthenticated Complaint Submission (HTTP 401)', unauthComplaint.status === 401);

    // 16. Reject Invalid Token (HTTP 403)
    const badTokenComplaint = await request('/api/complaints', 'POST', {
      category: 'Roads & Traffic',
      description: 'Pothole on main road',
    }, { Authorization: 'Bearer invalid.token.xyz' });
    report(16, 'Reject Complaint Submission with Invalid Token (HTTP 403)', badTokenComplaint.status === 403);

    // 17. Submit Complaint with Valid Image & Device GPS Coordinates via Multipart/form-data
    // Create a 1x1 test JPEG pixel buffer
    const sampleJpegBuffer = Buffer.from([
      0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x01, 0x00, 0x60,
      0x00, 0x60, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43, 0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08,
      0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01, 0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00,
      0x14, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x09, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00, 0x37, 0xFF, 0xD9
    ]);

    const captureTimestamp = new Date().toISOString();
    const testLatitude = 19.059624;
    const testLongitude = 72.829531;
    const testAccuracy = 3.8; // meters

    const submitRes = await multipartRequest(
      '/api/complaints',
      {
        category: 'Roads & Traffic',
        description: 'Dangerous pothole outside Metro Station causing traffic bottleneck.',
        priority: 'High',
        location: 'Linking Road, Bandra West, Mumbai, Maharashtra 400050',
        latitude: testLatitude.toString(),
        longitude: testLongitude.toString(),
        locationAccuracy: testAccuracy.toString(),
        locationCapturedAt: captureTimestamp,
      },
      {
        name: 'image',
        filename: 'pothole_evidence.jpg',
        contentType: 'image/jpeg',
        buffer: sampleJpegBuffer,
      },
      { Authorization: `Bearer ${tokenCitizen1}` }
    );

    report(
      17,
      'Submit Complaint with Multipart Image & Live GPS (HTTP 201 Created)',
      submitRes.status === 201 && submitRes.body.success === true && submitRes.body.complaint != null
    );
    const complaint1 = submitRes.body.complaint;

    // 18. Verify Schema & Values Stored in PostgreSQL:
    // Complaint ID, User ID, Image URL, Lat, Long, Accuracy, Capture Timestamp, Category, Description, Status
    const dbComplaint = await db.query('SELECT * FROM complaints WHERE id = $1', [complaint1.id]);
    const stored = dbComplaint.rows[0];
    const coordinatesVerified =
      stored.user_id === userCitizen1Id &&
      Math.abs(stored.latitude - testLatitude) < 0.0001 &&
      Math.abs(stored.longitude - testLongitude) < 0.0001 &&
      Math.abs(stored.location_accuracy - testAccuracy) < 0.1 &&
      stored.location_captured_at != null &&
      (stored.status === 'SUBMITTED' || stored.status === 'Pending') &&
      stored.image_url.startsWith('/uploads/complaint-');

    report(18, 'PostgreSQL Accuracy, Captured Timestamp, Coordinates, Status & Image Verified', coordinatesVerified);

    // 19. Confirm Photo is Saved and Retrievable via HTTP GET from Server Storage
    const imageHttpCheck = await request(stored.image_url, 'GET');
    report(
      19,
      'Image File Stored on Server & Retrievable via Static Uploads Route',
      imageHttpCheck.status === 200 && imageHttpCheck.headers['content-type']?.includes('image')
    );

    // 20. Reject Invalid Non-Image File Upload (e.g. .txt or .exe)
    const badFileRes = await multipartRequest(
      '/api/complaints',
      {
        category: 'Roads & Traffic',
        description: 'Test invalid upload',
        latitude: '19.0',
        longitude: '72.0',
      },
      {
        name: 'image',
        filename: 'malicious_script.exe',
        contentType: 'application/octet-stream',
        buffer: Buffer.from('MZ... not an image'),
      },
      { Authorization: `Bearer ${tokenCitizen1}` }
    );
    report(
      20,
      'Reject Invalid Non-Image File Formats (HTTP 400 Bad Request)',
      badFileRes.status === 400 && badFileRes.body.message.includes('Only image files')
    );

    // 21. Data Isolation: Citizen 2 calling ?onlyMine=true must NOT see Citizen 1\'s complaint
    const citizen2Reports = await request('/api/complaints?onlyMine=true', 'GET', null, {
      Authorization: `Bearer ${tokenCitizen2}`,
    });
    const leak = citizen2Reports.body.complaints.some(c => c.id === complaint1.id);
    report(21, 'Data Isolation Enforced on onlyMine Complaint History', citizen2Reports.status === 200 && !leak);

    // 22. Citizen 1 can retrieve their own complaint in Complaint History with full location metadata
    const citizen1Reports = await request('/api/complaints?onlyMine=true', 'GET', null, {
      Authorization: `Bearer ${tokenCitizen1}`,
    });
    const foundMine = citizen1Reports.body.complaints.find(c => c.id === complaint1.id);
    const historyMetadataComplete =
      foundMine != null &&
      foundMine.latitude != null &&
      foundMine.longitude != null &&
      foundMine.location_accuracy != null &&
      foundMine.location_captured_at != null &&
      foundMine.image_url != null;
    report(22, 'Complaint History Returns Full GPS & Image Metadata', historyMetadataComplete);

    // 23. Unauthorized Modification Prevention: Citizen 2 CANNOT modify Citizen 1\'s complaint
    const unauthModify = await request(`/api/complaints/${complaint1.id}`, 'PUT', {
      description: 'Hacked description by unauthorized user',
    }, { Authorization: `Bearer ${tokenCitizen2}` });
    report(
      23,
      'Prevent Unauthorized User from Modifying Other Citizen Complaint (HTTP 403)',
      unauthModify.status === 403 && unauthModify.body.message.includes('Forbidden')
    );

    // 24. Unauthorized Status Modification Prevention: Citizen 2 CANNOT change Citizen 1\'s status
    const unauthStatus = await request(`/api/complaints/${complaint1.id}/status`, 'PATCH', {
      status: 'VERIFIED',
    }, { Authorization: `Bearer ${tokenCitizen2}` });
    report(
      24,
      'Prevent Unauthorized User from Changing Complaint Status (HTTP 403)',
      unauthStatus.status === 403 && unauthStatus.body.message.includes('Forbidden')
    );

    // 25. Owner CAN Update Their Own Complaint Details
    const ownerUpdate = await request(`/api/complaints/${complaint1.id}`, 'PUT', {
      description: 'Updated description: Pothole width is approx 2 meters across.',
    }, { Authorization: `Bearer ${tokenCitizen1}` });
    report(
      25,
      'Allow Complaint Owner to Update Details (HTTP 200 OK)',
      ownerUpdate.status === 200 && ownerUpdate.body.complaint.description.includes('approx 2 meters')
    );

    // -------------------------------------------------------------
    // PART 3: ENTERPRISE FSM, RBAC & AUDIT LOGGING VERIFICATION
    // -------------------------------------------------------------
    console.log('\n--- PART 3: ENTERPRISE FSM, RBAC & AUDIT LOGGING VERIFICATION ---');

    // 26. Create Staff/Admin user to test authorized status update
    const staffEmail = `staff_${uid}@example.com`;
    const staffPass = 'StaffPassword@123';
    const staffPassHash = await bcrypt.hash(staffPass, 10);
    const staffUserRes = await db.query(`
      INSERT INTO users (name, email, password_hash, role, location, points, is_verified)
      VALUES ('Municipal Inspector', $1, $2, 'staff', 'Mumbai', 100, TRUE)
      RETURNING *
    `, [staffEmail, staffPassHash]);
    const staffUser = staffUserRes.rows[0];

    // Seed staff profile for this staff user
    const deptRes = await db.query("SELECT id FROM departments WHERE code = 'ROADS' LIMIT 1");
    const deptId = deptRes.rows[0]?.id || 1;
    await db.query(`
      INSERT INTO staff_profiles (user_id, department_id, employee_id, jurisdiction, max_capacity, current_load)
      VALUES ($1, $2, $3, 'Bandra West', 10, 0)
      ON CONFLICT (user_id) DO NOTHING
    `, [staffUser.id, deptId, `EMP-${uid}`]);

    const staffLogin = await request('/api/auth/login', 'POST', {
      identifier: staffEmail,
      password: staffPass,
    });
    const staffToken = staffLogin.body.token;
    report(
      26,
      'Staff Profile Association & Staff Session Authentication',
      staffLogin.status === 200 && staffToken != null && staffUser.role === 'staff'
    );

    // 27. Invalid FSM Transition: SUBMITTED -> RESOLVED directly should fail (HTTP 400)
    const invalidFsmRes = await request(`/api/complaints/${complaint1.id}/status`, 'PATCH', {
      status: 'RESOLVED',
      resolutionNotes: 'Skipping steps directly to resolved',
    }, { Authorization: `Bearer ${staffToken}` });
    report(
      27,
      'Reject Invalid FSM Transition SUBMITTED -> RESOLVED (HTTP 400)',
      invalidFsmRes.status === 400 && invalidFsmRes.body.message.includes('Invalid status transition')
    );

    // 28. Valid FSM Transition: SUBMITTED -> VERIFIED by Staff
    const verifyTransition = await request(`/api/complaints/${complaint1.id}/status`, 'PATCH', {
      status: 'VERIFIED',
      reason: 'Field photo and GPS verified by municipal inspector',
    }, { Authorization: `Bearer ${staffToken}` });
    report(
      28,
      'FSM Valid Transition: SUBMITTED -> VERIFIED by Authorized Staff',
      verifyTransition.status === 200 && verifyTransition.body.complaint.status === 'VERIFIED'
    );

    // 29. Valid FSM Transition: VERIFIED -> ASSIGNED (Updates staff workload)
    const assignTransition = await request(`/api/complaints/${complaint1.id}/status`, 'PATCH', {
      status: 'ASSIGNED',
      assignedTo: staffUser.id,
      departmentId: deptId,
      reason: 'Assigned to Bandra West Road Repair Unit',
    }, { Authorization: `Bearer ${staffToken}` });

    const updatedProfile = await db.query('SELECT current_load FROM staff_profiles WHERE user_id = $1', [staffUser.id]);
    report(
      29,
      'FSM Valid Transition: VERIFIED -> ASSIGNED & Increments Staff Workload',
      assignTransition.status === 200 &&
      assignTransition.body.complaint.status === 'ASSIGNED' &&
      updatedProfile.rows[0].current_load >= 1
    );

    // 30. Valid FSM Transition: ASSIGNED -> IN_PROGRESS & Records Response Time
    const inProgressTransition = await request(`/api/complaints/${complaint1.id}/status`, 'PATCH', {
      status: 'IN_PROGRESS',
      reason: 'Repair crew dispatched to site',
    }, { Authorization: `Bearer ${staffToken}` });

    const slaRecord1 = await db.query('SELECT responded_at FROM sla_records WHERE complaint_id = $1', [complaint1.id]);
    report(
      30,
      'FSM Valid Transition: ASSIGNED -> IN_PROGRESS & Logs SLA Responded Milestone',
      inProgressTransition.status === 200 &&
      inProgressTransition.body.complaint.status === 'IN_PROGRESS' &&
      slaRecord1.rows[0]?.responded_at != null
    );

    // 31. Reject Transition to RESOLVED without Resolution Notes (HTTP 400)
    const badResolveRes = await request(`/api/complaints/${complaint1.id}/status`, 'PATCH', {
      status: 'RESOLVED',
      resolutionNotes: '', // empty
    }, { Authorization: `Bearer ${staffToken}` });
    report(
      31,
      'Reject RESOLVED Transition with Empty Resolution Notes (HTTP 400)',
      badResolveRes.status === 400 && badResolveRes.body.message.includes('resolution notes')
    );

    // 32. Valid FSM Transition: IN_PROGRESS -> RESOLVED with Resolution Notes & Award Points
    const resolveTransition = await request(`/api/complaints/${complaint1.id}/status`, 'PATCH', {
      status: 'RESOLVED',
      resolutionNotes: 'Pothole asphalt resurfaced and road cleared.',
    }, { Authorization: `Bearer ${staffToken}` });

    const updatedUser1 = await db.query('SELECT points FROM users WHERE id = $1', [userCitizen1Id]);
    const slaRecord2 = await db.query('SELECT resolved_at FROM sla_records WHERE complaint_id = $1', [complaint1.id]);
    report(
      32,
      'FSM Valid Transition: IN_PROGRESS -> RESOLVED, SLA Marked & Bonus Points Awarded',
      resolveTransition.status === 200 &&
      resolveTransition.body.complaint.status === 'RESOLVED' &&
      slaRecord2.rows[0]?.resolved_at != null &&
      updatedUser1.rows[0].points >= 45
    );

    // 33. Unauthorized Citizen CANNOT Close Another Citizen\'s Resolved Complaint
    const unauthClose = await request(`/api/complaints/${complaint1.id}/status`, 'PATCH', {
      status: 'CLOSED',
    }, { Authorization: `Bearer ${tokenCitizen2}` });
    report(
      33,
      'Prevent Unauthorized Citizen from Closing Other Citizen Resolved Complaint (HTTP 403)',
      unauthClose.status === 403
    );

    // 34. Owner Citizen CAN Close Their Own Resolved Complaint
    const ownerClose = await request(`/api/complaints/${complaint1.id}/status`, 'PATCH', {
      status: 'CLOSED',
      reason: 'Citizen confirmed road repair completed satisfactory',
    }, { Authorization: `Bearer ${tokenCitizen1}` });
    report(
      34,
      'Owner Citizen Confirms & Closes Their Own Resolved Complaint (RESOLVED -> CLOSED)',
      ownerClose.status === 200 && ownerClose.body.complaint.status === 'CLOSED'
    );

    // 35. Audit Timeline: GET /api/complaints/:id/history returns complete chronological history
    const historyRes = await request(`/api/complaints/${complaint1.id}/history`, 'GET');
    const history = historyRes.body.history || [];
    const hasInitial = history.some(h => h.to_status === 'SUBMITTED');
    const hasVerified = history.some(h => h.to_status === 'VERIFIED');
    const hasAssigned = history.some(h => h.to_status === 'ASSIGNED');
    const hasInProgress = history.some(h => h.to_status === 'IN_PROGRESS');
    const hasResolved = history.some(h => h.to_status === 'RESOLVED');
    const hasClosed = history.some(h => h.to_status === 'CLOSED');
    report(
      35,
      'Complaint Audit History Timeline Returns Complete FSM Transition Trail',
      historyRes.status === 200 &&
      hasInitial && hasVerified && hasAssigned && hasInProgress && hasResolved && hasClosed
    );

    // 36. Public Self-Registration Ignores Client Role Escalation
    const hackerReg = await request('/api/auth/register', 'POST', {
      name: 'Sneaky Attacker',
      email: `attacker_${uid}@example.com`,
      password: 'HackerPassword@123',
      role: 'super_admin', // Attempted role escalation
    });
    const hackerDb = await db.query('SELECT role FROM users WHERE email = $1', [`attacker_${uid}@example.com`]);
    report(
      36,
      'Self-Registration Enforces Role Guarding (Client role escalation rejected, role=user)',
      hackerReg.status === 201 && hackerDb.rows[0]?.role === 'user'
    );

    // 37. GET /api/auth/me returns User, Staff Profile, and Department
    const meRes = await request('/api/auth/me', 'GET', null, { Authorization: `Bearer ${staffToken}` });
    report(
      37,
      'GET /api/auth/me Returns Role, Department & Staff Metadata',
      meRes.status === 200 &&
      meRes.body.user.role === 'staff' &&
      meRes.body.user.department_code === 'ROADS' &&
      meRes.body.user.jurisdiction === 'Bandra West'
    );

    // 38. POST /api/auth/logout Revokes Active Session
    const logoutRes = await request('/api/auth/logout', 'POST', {}, { Authorization: `Bearer ${staffToken}` });
    report(
      38,
      'POST /api/auth/logout Revokes Active Token Session in PostgreSQL',
      logoutRes.status === 200 && logoutRes.body.success === true
    );

    // 39. Revoked Token Access Rejected (HTTP 401 Session Revoked)
    const revokedCheck = await request('/api/auth/me', 'GET', null, { Authorization: `Bearer ${staffToken}` });
    report(
      39,
      'Subsequent API Request with Revoked Token Rejected (HTTP 401 Session Revoked)',
      revokedCheck.status === 401 && revokedCheck.body.message.includes('Session has been revoked')
    );

    // -------------------------------------------------------------
    // PART 4: IMAGE INTEGRITY (SHA-256) & PERCEPTUAL HASHING (pHash)
    // -------------------------------------------------------------
    console.log('\n--- PART 4: IMAGE INTEGRITY (SHA-256) & PERCEPTUAL HASHING (pHash) ---');

    // Generate realistic civic evidence test images
    const potholeSvg = Buffer.from(`
      <svg width="200" height="200" xmlns="http://www.w3.org/2000/svg">
        <defs>
          <linearGradient id="road" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0%" stop-color="#4a4a4a"/>
            <stop offset="50%" stop-color="#333333"/>
            <stop offset="100%" stop-color="#555555"/>
          </linearGradient>
        </defs>
        <rect width="200" height="200" fill="url(#road)"/>
        <ellipse cx="95" cy="115" rx="55" ry="35" fill="#1a1a1a"/>
        <ellipse cx="100" cy="120" rx="40" ry="22" fill="#0a0a0a"/>
        <path d="M 30,50 Q 80,90 140,45 T 190,80" stroke="#222222" stroke-width="6" fill="none"/>
        <circle cx="160" cy="150" r="15" fill="#2a2a2a"/>
      </svg>
    `);
    const potholePngBuffer = await sharp(potholeSvg).png().toBuffer();

    // 40. Submit Complaint with Realistic Image and Verify SHA-256 and pHash Storage
    const potholeComplaintRes = await multipartRequest(
      '/api/complaints',
      {
        category: 'Roads & Traffic',
        description: 'Large pothole near Bandra station road.',
        priority: 'High',
        location: 'Station Road, Bandra West, Mumbai',
        latitude: '19.055',
        longitude: '72.840',
      },
      {
        name: 'image',
        filename: 'pothole_original.png',
        contentType: 'image/png',
        buffer: potholePngBuffer,
      },
      { Authorization: `Bearer ${tokenCitizen1}` }
    );

    const potholeComplaint = potholeComplaintRes.body.complaint;
    const potholeAnalysis = potholeComplaintRes.body.imageAnalysis;

    const imgDbRecord = await db.query(
      'SELECT * FROM complaint_images WHERE complaint_id = $1 ORDER BY id DESC LIMIT 1',
      [potholeComplaint.id]
    );
    const storedImage = imgDbRecord.rows[0];

    report(
      40,
      'Complaint Submission Computes & Stores SHA-256 and pHash in PostgreSQL',
      potholeComplaintRes.status === 201 &&
      storedImage != null &&
      storedImage.sha256_hash.length === 64 &&
      storedImage.phash != null &&
      storedImage.phash.length === 16 &&
      potholeAnalysis != null &&
      potholeAnalysis.sha256 === storedImage.sha256_hash
    );

    // 41. Image Cryptographic Integrity Verification (Algorithm 5)
    const integrityRes = await request(`/api/complaints/images/${storedImage.id}/verify`, 'GET');
    report(
      41,
      'Image Integrity Verification Route Confirms Disk SHA-256 Matches Database',
      integrityRes.status === 200 &&
      integrityRes.body.verification.valid === true &&
      integrityRes.body.verification.currentHash === storedImage.sha256_hash
    );

    // 42. Multi-Image Evidence Upload (POST /api/complaints/:id/images)
    const secondPhotoBuffer = await sharp(potholePngBuffer).rotate(90).png().toBuffer();
    const addPhotoRes = await multipartRequest(
      `/api/complaints/${potholeComplaint.id}/images`,
      {},
      {
        name: 'image',
        filename: 'pothole_angle2.png',
        contentType: 'image/png',
        buffer: secondPhotoBuffer,
      },
      { Authorization: `Bearer ${tokenCitizen1}` }
    );
    report(
      42,
      'Multi-Image Evidence: Add Second Evidence Photo to Existing Complaint (HTTP 201)',
      addPhotoRes.status === 201 &&
      addPhotoRes.body.image != null &&
      addPhotoRes.body.analysis.sha256 != null
    );

    // 43. Retrieve All Images for a Complaint (GET /api/complaints/:id/images)
    const allImagesRes = await request(`/api/complaints/${potholeComplaint.id}/images`, 'GET');
    report(
      43,
      'Retrieve All Evidence Photos with Hashes for a Complaint (count >= 2)',
      allImagesRes.status === 200 &&
      allImagesRes.body.count >= 2 &&
      allImagesRes.body.images[0].sha256_hash != null
    );

    // 44. Exact Binary Duplicate Detection (Algorithm 5)
    // Upload the EXACT same image buffer again
    const exactDupRes = await multipartRequest(
      '/api/complaints',
      {
        category: 'Roads & Traffic',
        description: 'Duplicate report of same pothole with same file.',
        priority: 'High',
        location: 'Station Road, Bandra West',
      },
      {
        name: 'image',
        filename: 'pothole_copy.png',
        contentType: 'image/png',
        buffer: potholePngBuffer,
      },
      { Authorization: `Bearer ${tokenCitizen2}` }
    );
    report(
      44,
      'Exact Binary Duplicate Detection via SHA-256 (isExactDuplicate: true, score: 100)',
      exactDupRes.status === 201 &&
      exactDupRes.body.imageAnalysis != null &&
      exactDupRes.body.imageAnalysis.isExactDuplicate === true &&
      exactDupRes.body.imageAnalysis.duplicateOfId === potholeComplaint.id
    );

    // 45. Perceptual Near-Duplicate Detection (Algorithm 6 - pHash)
    // Create a modified version of the same pothole photo: resized to 280x280 and JPEG compressed (quality 75)
    const compressedPotholeBuffer = await sharp(potholePngBuffer)
      .resize(280, 280)
      .jpeg({ quality: 75 })
      .toBuffer();

    const visualDupRes = await multipartRequest(
      '/api/complaints',
      {
        category: 'Roads & Traffic',
        description: 'Citizen re-reported pothole using resized camera photo.',
        priority: 'High',
        location: 'Station Road, Bandra West',
      },
      {
        name: 'image',
        filename: 'pothole_compressed.jpg',
        contentType: 'image/jpeg',
        buffer: compressedPotholeBuffer,
      },
      { Authorization: `Bearer ${tokenCitizen2}` }
    );
    const expectedIds = [potholeComplaint.id, exactDupRes.body?.complaint?.id];
    report(
      45,
      'Perceptual Near-Duplicate Detection via pHash (isVisualDuplicate: true, distance <= 10)',
      visualDupRes.status === 201 &&
      visualDupRes.body.imageAnalysis != null &&
      visualDupRes.body.imageAnalysis.isVisualDuplicate === true &&
      visualDupRes.body.imageAnalysis.hammingDistance <= 10 &&
      expectedIds.includes(visualDupRes.body.imageAnalysis.duplicateOfId),
      `[Dist: ${visualDupRes.body.imageAnalysis?.hammingDistance}, MatchId: ${visualDupRes.body.imageAnalysis?.duplicateOfId}]`
    );

    // 46. Distinct Visual Image is NOT Flagged as Duplicate
    const lightSvg = Buffer.from(`
      <svg width="200" height="200" xmlns="http://www.w3.org/2000/svg">
        <rect width="200" height="200" fill="#050515"/>
        <circle cx="100" cy="60" r="35" fill="#fffbe6"/>
        <line x1="100" y1="60" x2="100" y2="200" stroke="#888888" stroke-width="12"/>
      </svg>
    `);
    const lightPngBuffer = await sharp(lightSvg).png().toBuffer();

    const distinctRes = await multipartRequest(
      '/api/complaints',
      {
        category: 'Street & Public Lighting',
        description: 'Broken streetlight at night alley.',
        priority: 'Medium',
        location: 'Carter Road, Bandra West',
      },
      {
        name: 'image',
        filename: 'streetlight_broken.png',
        contentType: 'image/png',
        buffer: lightPngBuffer,
      },
      { Authorization: `Bearer ${tokenCitizen1}` }
    );
    report(
      46,
      'Distinct Visual Scene Not Flagged as Duplicate (isExactDuplicate: false, isVisualDuplicate: false)',
      distinctRes.status === 201 &&
      distinctRes.body.imageAnalysis != null &&
      distinctRes.body.imageAnalysis.isExactDuplicate === false &&
      distinctRes.body.imageAnalysis.isVisualDuplicate === false
    );

    // 47. Pre-submission Image Duplicate Check Endpoint (POST /api/complaints/images/check-duplicate)
    const checkDupRes = await multipartRequest(
      '/api/complaints/images/check-duplicate',
      {},
      {
        name: 'image',
        filename: 'pre_check_test.png',
        contentType: 'image/png',
        buffer: potholePngBuffer,
      }
    );
    report(
      47,
      'Pre-Submission Duplicate Screening Endpoint Identifies Existing Duplicates',
      checkDupRes.status === 200 &&
      checkDupRes.body.isExactDuplicate === true &&
      checkDupRes.body.exactMatch.complaint_id === potholeComplaint.id
    );

    // -------------------------------------------------------------
    // PART 5: ESSENTIAL MOBILE APPLICATION ALGORITHMS VERIFICATION
    // -------------------------------------------------------------
    console.log('\n--- PART 5: ESSENTIAL MOBILE ALGORITHMS VERIFICATION ---');

    // 48. Algorithm 1: Rule-Based Complaint Classification (POST /api/complaints/classify)
    const classifyRoads = await request('/api/complaints/classify', 'POST', {
      text: 'Deep crater and broken asphalt on main junction causing traffic delays.',
    });
    const classifyWater = await request('/api/complaints/classify', 'POST', {
      text: 'Major pipeline burst with contaminated sewage flooding the street.',
    });
    const classifyLights = await request('/api/complaints/classify', 'POST', {
      text: 'Streetlights flickering and completely dark alley causing electrocution hazard.',
    });

    report(
      48,
      'Rule-Based Complaint Classification (Algorithm 1: Predicts Category & Dept from Text)',
      classifyRoads.status === 200 &&
      classifyRoads.body.category === 'Roads & Traffic' &&
      classifyWater.body.category === 'Water Supply & Drainage' &&
      classifyLights.body.category === 'Street & Public Lighting' &&
      classifyRoads.body.deptCode === 'ROADS'
    );

    // 49. Algorithm 9: Rule-Based Municipal Department Routing
    const autoRoutedComplaint = await request('/api/complaints', 'POST', {
      category: 'Street & Public Lighting',
      description: 'Dangling live wire from broken lamppost.',
      priority: 'High',
      location: 'Linking Road, Bandra West',
      latitude: 19.060,
      longitude: 72.836,
    }, { Authorization: `Bearer ${tokenCitizen1}` });

    const lightingDept = await db.query("SELECT id FROM departments WHERE code = 'LIGHTING' LIMIT 1");
    report(
      49,
      'Automated Department Routing (Algorithm 9: Directs to Lighting Dept in PostgreSQL)',
      autoRoutedComplaint.status === 201 &&
      autoRoutedComplaint.body.complaint.department_id === lightingDept.rows[0].id
    );

    // 50. Algorithm 8: Weighted Priority Scoring (P = 0.25S + 0.20U + 0.15C + 0.15G + 0.10R + 0.15A)
    report(
      50,
      'Weighted Priority Scoring (Algorithm 8: Calculates Explainable Priority Score [0-100])',
      autoRoutedComplaint.body.priorityAnalysis != null &&
      autoRoutedComplaint.body.complaint.priority_score != null &&
      autoRoutedComplaint.body.complaint.priority_score >= 50 &&
      autoRoutedComplaint.body.priorityAnalysis.breakdown.severity >= 80
    );

    // 51. Algorithm 11: Haversine Distance Calculation & Nearby Spatial Queries (GET /api/complaints/nearby)
    // Query near Bandra West (19.055, 72.840) within 1500m radius
    const nearbyRes = await request('/api/complaints/nearby?lat=19.055&lng=72.840&radius=1500', 'GET');
    report(
      51,
      'Spatial Proximity Queries via Haversine Formula (Algorithm 11: Accurately finds nearby complaints)',
      nearbyRes.status === 200 &&
      nearbyRes.body.count >= 1 &&
      nearbyRes.body.complaints[0].distanceMeters != null &&
      nearbyRes.body.complaints[0].distanceMeters <= 1500
    );

    // 52. Haversine Distance Filters Out Distant Complaints (> 50 km)
    // Query near Colaba (18.906, 72.814) with 1000m radius — Bandra complaints should NOT appear
    const distantRes = await request('/api/complaints/nearby?lat=18.906&lng=72.814&radius=1000', 'GET');
    report(
      52,
      'Haversine Distance Correctly Excludes Out-of-Range Complaints (> 15km away)',
      distantRes.status === 200 &&
      distantRes.body.count === 0
    );

    // 53. Algorithm 7: Multi-modal Pre-Submission Duplicate Screening (POST /api/complaints/check-duplicate)
    // Check duplicate using same location (19.055, 72.840) and similar text
    const multiModalDupRes = await request('/api/complaints/check-duplicate', 'POST', {
      latitude: 19.055,
      longitude: 72.840,
      category: 'Roads & Traffic',
      description: 'Major pothole crater on Station Road causing traffic congestion.',
    });
    report(
      53,
      'Multi-Modal Pre-Submission Duplicate Warning (Algorithm 7: Fuses GPS + Time + Text)',
      multiModalDupRes.status === 200 &&
      multiModalDupRes.body.isDuplicate === true &&
      multiModalDupRes.body.spatiotemporal != null &&
      multiModalDupRes.body.spatiotemporal.isDuplicate === true &&
      multiModalDupRes.body.warningMessage != null
    );

    // 54. Complaint Lifecycle Tracking & Status History for Mobile App (GET /api/complaints/:id/history)
    const mobileHistoryRes = await request(`/api/complaints/${complaint1.id}/history`, 'GET');
    report(
      54,
      'Complaint Tracking & Status History for Flutter UI (Algorithms 13 & 18)',
      mobileHistoryRes.status === 200 &&
      mobileHistoryRes.body.history != null &&
      mobileHistoryRes.body.history.length >= 4 &&
      mobileHistoryRes.body.history[0].to_status != null
    );

    console.log('\n======================================================================');
    console.log(`📊 Comprehensive Test Results: ${passed} Passed, ${failed} Failed`);
    console.log('======================================================================\n');

    process.exit(failed > 0 ? 1 : 0);
  } catch (err) {
    console.error('Unexpected test execution failure:', err);
    process.exit(1);
  }
}

// Start server and run tests
const app = require('./server');
setTimeout(runTests, 1500);

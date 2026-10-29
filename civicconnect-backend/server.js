const express = require('express');
const cors = require('cors');
const path = require('path');
const fs = require('fs');
require('dotenv').config();

const db = require('./db');
const authRoutes = require('./routes/auth');
const complaintsRoutes = require('./routes/complaints');
const notificationsRoutes = require('./routes/notifications');
const rewardsRoutes = require('./routes/rewards');

const app = express();
const PORT = process.env.PORT || 5000;

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Ensure uploads directory exists and serve statically
const uploadDir = path.join(__dirname, 'uploads');
if (!fs.existsSync(uploadDir)) {
  fs.mkdirSync(uploadDir, { recursive: true });
}
app.use('/uploads', express.static(uploadDir));

// Health check endpoint
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', message: 'CivicConnect API is running smoothly' });
});

// API Routes
app.use('/api/auth', authRoutes);
app.use('/api/complaints', complaintsRoutes);
app.use('/api/notifications', notificationsRoutes);
app.use('/api/rewards', rewardsRoutes);

// Auto-initialize PostgreSQL tables if connected
async function initDatabase() {
  try {
    const schemaSql = fs.readFileSync(path.join(__dirname, 'schema.sql'), 'utf-8');
    await db.query(schemaSql);
    console.log('✅ PostgreSQL database tables verified/initialized successfully.');
  } catch (err) {
    console.warn('⚠️ Could not automatically run schema.sql. Ensure PostgreSQL is running and credentials in .env are correct:', err.message);
  }
}

// Global error handler
app.use((err, req, res, next) => {
  console.error('Server error caught:', err.message || err);
  if (err.name === 'MulterError') {
    if (err.code === 'LIMIT_FILE_SIZE') {
      return res.status(400).json({ success: false, message: 'Image size exceeds the 10MB limit.' });
    }
    return res.status(400).json({ success: false, message: `Upload error: ${err.message}` });
  }
  if (err.message && err.message.includes('Only image files')) {
    return res.status(400).json({ success: false, message: err.message });
  }
  res.status(err.status || 500).json({ success: false, message: err.message || 'Internal Server Error' });
});

app.listen(PORT, async () => {
  console.log(`🚀 CivicConnect Backend Server running on http://localhost:${PORT}`);
  await initDatabase();
});

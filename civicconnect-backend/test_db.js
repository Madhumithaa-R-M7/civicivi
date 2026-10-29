const db = require('./db');
const fs = require('fs');

async function testConnection() {
  console.log('Testing connection to PostgreSQL...');
  try {
    const res = await db.query('SELECT NOW()');
    console.log('✅ PostgreSQL connected! Server time:', res.rows[0].now);

    const schemaSql = fs.readFileSync('./schema.sql', 'utf-8');
    await db.query(schemaSql);
    console.log('✅ All tables verified/created successfully in civicconnect database!');

    const tables = await db.query(`
      SELECT table_name 
      FROM information_schema.tables 
      WHERE table_schema = 'public' 
      ORDER BY table_name;
    `);
    console.log('📊 Existing tables:', tables.rows.map(r => r.table_name).join(', '));
    process.exit(0);
  } catch (err) {
    console.error('❌ Connection or schema error:', err.message);
    process.exit(1);
  }
}

testConnection();

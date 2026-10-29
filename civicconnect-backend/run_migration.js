const db = require('./db');
const fs = require('fs');
const path = require('path');

async function runMigration() {
  try {
    const migrationFile = process.argv[2] || '002_enterprise_schema.sql';
    const filePath = path.join(__dirname, 'migrations', migrationFile);
    console.log(`Applying migration: ${filePath}`);
    const sql = fs.readFileSync(filePath, 'utf8');
    await db.query(sql);
    console.log(`✅ Migration ${migrationFile} applied successfully!`);
    process.exit(0);
  } catch (err) {
    console.error('❌ Migration failed:', err.message);
    process.exit(1);
  }
}

runMigration();

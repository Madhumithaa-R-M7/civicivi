const db = require('./db');

async function main() {
  try {
    const res = await db.query(`
      SELECT table_name 
      FROM information_schema.tables 
      WHERE table_schema = 'public' 
      ORDER BY table_name;
    `);
    console.log('Tables in civicconnect database:');
    console.table(res.rows);

    const depts = await db.query('SELECT id, name, code FROM departments;');
    console.log('\nSeeded Departments:');
    console.table(depts.rows);

    process.exit(0);
  } catch (err) {
    console.error('Error checking schema:', err);
    process.exit(1);
  }
}

main();

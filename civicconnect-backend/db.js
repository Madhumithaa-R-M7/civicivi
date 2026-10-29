const { Pool } = require('pg');
const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '.env') });

const poolConfig = process.env.DATABASE_URL
  ? {
      connectionString: process.env.DATABASE_URL,
      connectionTimeoutMillis: 5000,
    }
  : {
      user: process.env.DB_USER || 'postgres',
      host: process.env.DB_HOST || 'localhost',
      database: process.env.DB_NAME || 'civicconnect',
      password: String(process.env.DB_PASSWORD || 'its_civic'),
      port: parseInt(process.env.DB_PORT || '5432', 10),
      connectionTimeoutMillis: 5000,
    };

const pool = new Pool(poolConfig);

pool.on('connect', () => {
  // Connection verified
});

pool.on('error', (err) => {
  console.error('Unexpected error on idle PostgreSQL client pool:', err.message);
});

module.exports = {
  query: (text, params) => pool.query(text, params),
  pool,
};

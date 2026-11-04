import { Pool } from "pg";

// One pool per server process. DATABASE_URL (with sslmode=require) comes
// from /etc/nextjs/app.env; NODE_EXTRA_CA_CERTS lets node-postgres verify
// the RDS certificate.
const globalForPg = globalThis;

export const pool =
  globalForPg.__pgPool ??
  new Pool({
    connectionString: process.env.DATABASE_URL,
    max: 5,
    connectionTimeoutMillis: 5000,
  });

globalForPg.__pgPool = pool;

let schemaReady;

export function ensureSchema() {
  schemaReady ??= pool
    .query(
      `CREATE TABLE IF NOT EXISTS visits (
         id         BIGSERIAL PRIMARY KEY,
         visited_at TIMESTAMPTZ NOT NULL DEFAULT now(),
         user_agent TEXT
       )`,
    )
    .catch((err) => {
      schemaReady = undefined;
      throw err;
    });
  return schemaReady;
}

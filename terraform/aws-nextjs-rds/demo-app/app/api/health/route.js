import { pool } from "../../../lib/db";

export const dynamic = "force-dynamic";

// Polled by the Terraform health check: 200 only when the app can query RDS.
export async function GET() {
  const started = Date.now();
  try {
    const { rows } = await pool.query(
      "SELECT current_setting('server_version') AS version, (SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()) AS ssl",
    );
    return Response.json({
      status: "ok",
      database: "ok",
      postgres_version: rows[0].version,
      tls: rows[0].ssl,
      latency_ms: Date.now() - started,
    });
  } catch (err) {
    return Response.json(
      { status: "degraded", database: "error", error: err.message },
      { status: 503 },
    );
  }
}

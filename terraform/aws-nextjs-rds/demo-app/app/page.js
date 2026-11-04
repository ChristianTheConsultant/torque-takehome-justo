import os from "node:os";
import { headers } from "next/headers";
import { ensureSchema, pool } from "../lib/db";

// Every request hits the database; nothing is prerendered at build time.
export const dynamic = "force-dynamic";

async function loadData() {
  try {
    await ensureSchema();
    const userAgent = (await headers()).get("user-agent") ?? "unknown";
    await pool.query("INSERT INTO visits (user_agent) VALUES ($1)", [userAgent.slice(0, 300)]);

    const [stats, recent] = await Promise.all([
      pool.query(`
        SELECT (SELECT count(*) FROM visits)::int                     AS total,
               current_setting('server_version')                      AS version,
               current_database()                                     AS database,
               now()                                                  AS db_time,
               (SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()) AS tls`),
      pool.query("SELECT id, visited_at, user_agent FROM visits ORDER BY id DESC LIMIT 5"),
    ]);
    return { ok: true, stats: stats.rows[0], recent: recent.rows };
  } catch (err) {
    return { ok: false, error: err.message };
  }
}

export default async function Home() {
  const data = await loadData();
  const dbHost = (() => {
    try {
      return new URL(process.env.DATABASE_URL).hostname;
    } catch {
      return "not configured";
    }
  })();

  return (
    <main>
      <p className="eyebrow">Deployed by Quali Torque</p>
      <h1>Next.js on EC2, backed by RDS PostgreSQL</h1>

      <section className={`status ${data.ok ? "ok" : "err"}`}>
        <span className="dot" />
        {data.ok ? "Database connected" : `Database error: ${data.error}`}
      </section>

      {data.ok && (
        <>
          <section className="grid">
            <Stat label="Page views (stored in RDS)" value={data.stats.total} />
            <Stat label="PostgreSQL" value={data.stats.version} />
            <Stat label="Database" value={data.stats.database} />
            <Stat label="TLS to RDS" value={data.stats.tls ? "on" : "off"} />
          </section>

          <h2>Latest visits</h2>
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>#</th>
                  <th>When (UTC)</th>
                  <th>User agent</th>
                </tr>
              </thead>
              <tbody>
                {data.recent.map((row) => (
                  <tr key={row.id}>
                    <td>{row.id}</td>
                    <td>{new Date(row.visited_at).toISOString().replace("T", " ").slice(0, 19)}</td>
                    <td className="ua">{row.user_agent}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}

      <footer>
        <span>EC2 host: {os.hostname()}</span>
        <span>RDS host: {dbHost}</span>
        <span>Node {process.version}</span>
        <a href="/api/health">/api/health</a>
      </footer>
    </main>
  );
}

function Stat({ label, value }) {
  return (
    <div className="stat">
      <div className="value">{String(value)}</div>
      <div className="label">{label}</div>
    </div>
  );
}

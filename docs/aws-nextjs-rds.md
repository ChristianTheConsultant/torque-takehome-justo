# Next.js on EC2 + RDS (AWS test blueprint)

Blueprints: [`blueprints/aws-nextjs-rds.yaml`](../blueprints/aws-nextjs-rds.yaml) (built-in demo app) and [`blueprints/aws-chessu.yaml`](../blueprints/aws-chessu.yaml) ([chessu](https://github.com/dotnize/chessu) multiplayer chess)
Module: [`terraform/aws-nextjs-rds/`](../terraform/aws-nextjs-rds/)

A proof-of-functionality environment: a Next.js app on one small EC2 instance, talking to a single-AZ RDS PostgreSQL database, in a dedicated VPC. The Terraform grain stays running until the app passes an HTTP health check, so an **Active** environment means the whole path (browser → EC2 → RDS) works.

## What gets created

| Resource | Size / setting | Why |
|---|---|---|
| VPC, 2 public + 2 private subnets, IGW | no NAT gateway | NAT is ~$32/month; RDS needs no internet access |
| EC2 (Amazon Linux 2023) | `t3.small`, 20 GiB gp3, IMDSv2 | 2 GiB builds most Next.js apps; swap is added on smaller sizes |
| RDS PostgreSQL 16 | `db.t4g.micro`, 20 GiB gp3, single-AZ, no backups | cheapest RDS option, destroyed cleanly with no snapshot |
| Security groups | app port from `allowed_cidr`; 5432 only from the web SG | DB is never reachable from outside the VPC |
| IAM role + instance profile | SSM Session Manager + read one SSM parameter | shell access with no SSH key or port 22 |
| SSM SecureString | `/<name_prefix>/database-url` | the generated DB password never appears in user data or Torque inputs |

Rough on-demand cost in us-east-1: **~$0.05/hour** (~$1.20/day) while running.

## Boot sequence

[`scripts/bootstrap.sh`](../terraform/aws-nextjs-rds/scripts/bootstrap.sh) runs once via cloud-init:

1. Adds a 2 GiB swap file if RAM < 3 GiB.
2. Installs Node.js (`node_version`, default 22.14.0) from nodejs.org and enables corepack for pnpm/yarn. Node 22.14+ is needed because older corepack releases fail signature checks on current pnpm and yarn downloads.
3. Copies the built-in demo app, or `git clone`s `app_repo_url` at `app_git_ref`.
4. Waits for the database URL parameter (RDS is created in parallel), downloads the RDS CA bundle and writes `/etc/nextjs/app.env`. That file holds `DATABASE_URL` plus the same connection split into `PGHOST`/`PGPORT`/`PGUSER`/`PGPASSWORD`/`PGDATABASE`/`PGSSLMODE`, for apps that call `new pg.Pool()` with no config. It also holds `PORT`, `APP_URL` (`http://<public-ip>`), `APP_SECRET` (random, generated on the instance), `NODE_EXTRA_CA_CERTS` and finally `app_extra_env`.
5. Runs install → build → optional migrate. The package manager is detected from the lockfile, and each step can be overridden.
6. Starts a `nextjs` systemd service on port 80, run as an unprivileged user with `CAP_NET_BIND_SERVICE`. If `app_backend_start_command` is set, it also starts a `nextjs-backend` service from the same directory and environment.

## Demo app

[`demo-app/`](../terraform/aws-nextjs-rds/demo-app/) is a Next.js 15 App Router app written in plain JS with `pg` as its only extra dependency. Each page view inserts a row into a `visits` table and shows the running count, the PostgreSQL version and whether the connection uses TLS. `/api/health` returns 200 only when a query to RDS succeeds; the Terraform health check polls this endpoint.

## Deploying a different Next.js project

Set `app_repo_url` (and `app_git_ref`) at launch. Most real projects also need extra env vars and some build tweaks. The module supports these through grain inputs; [`aws-chessu.yaml`](../blueprints/aws-chessu.yaml) is a worked example.

```yaml
- app_subdir: apps/web                            # monorepos
- app_install_command: pnpm install --frozen-lockfile
- app_build_command: pnpm build
- app_migrate_command: npx prisma migrate deploy
- app_start_command: pnpm start
- app_backend_start_command: 'PORT=3001 pnpm start:server'   # optional second process
- app_extra_ports: '[3001]'                       # opened to allowed_cidr
- app_extra_env: '{ "NEXTAUTH_URL": "$APP_URL", "AUTH_SECRET": "$APP_SECRET" }'
- health_check_path: /                            # defaults to / for custom repos
- extra_health_checks: '[{ "port": 3001, "path": "/health" }]'
```

`app_extra_env` values may reference `$APP_URL`, `$APP_SECRET` and the `PG*` variables. Use bare `$NAME`: they're expanded on the instance, and `${NAME}` would be treated as Terraform interpolation.

## chessu

[`aws-chessu.yaml`](../blueprints/aws-chessu.yaml) deploys [dotnize/chessu](https://github.com/dotnize/chessu) (MIT): a Next.js 14 client on port 80 and an Express/socket.io API on port 3001, which stores users, finished games and sessions in RDS. Getting it running on this stack needed the following:

| Problem | Handling |
|---|---|
| The API calls `new pg.Pool()` with no config, so it reads `PG*` env vars and ignores `DATABASE_URL` | The bootstrap exports the `PG*` variables, with `PGSSLMODE=require` |
| In `NODE_ENV=production` the session cookie is `Secure` + `SameSite=None`, which browsers drop over plain HTTP, so every socket is disconnected with "no session" | The API runs without `NODE_ENV=production`, which makes the cookie `SameSite=Lax`. That works because `:80` and `:3001` on one IP are the same site |
| The browser talks to the API directly, and `NEXT_PUBLIC_API_URL` is baked in at build time | The client is built on the instance with `NEXT_PUBLIC_API_URL=$APP_URL:3001`, and the API gets `CORS_ORIGIN=$APP_URL` |
| No `packageManager` field; the lockfile pins Next 14.2.5, which has known CVEs | Pin pnpm 9.15.9 with `corepack use`, then `pnpm --filter @chessu/client update next@14` (14.2.35 when tested) |
| Server-rendered pages fetch the API through its public URL | The instance calls its own public IP on `:3001`, so `allowed_cidr` must cover it. The default `0.0.0.0/0` does |

The health checks require `/` on port 80 and `/v1/games` on port 3001 to respond. The API only starts listening after it has connected to RDS, so a passing API check proves the database path too. To play, open `app_url`, continue as a guest, create a game, and open the invite link in a second browser.

## Known trade-offs

- **The health check runs from the Torque agent.** `allowed_cidr` must include the agent's egress IP; the default `0.0.0.0/0` does.
- **The health check also runs on destroy.** Terraform re-reads data sources on destroy, so if the app is dead at teardown the destroy retries for `health_check_timeout_minutes` and then fails. Set `wait_for_app = false` for environments you expect to break.
- **Plain HTTP on a public IP.** There's no ALB, TLS certificate or DNS, which is acceptable for a short-lived test.
- **`app_extra_env` values are sourced by bash on the instance.** That's what makes `$APP_URL`-style references work, but it also means spaces, quotes or a literal `$` in a value need shell escaping.

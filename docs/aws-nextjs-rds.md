# Next.js on EC2 + RDS (AWS test blueprint)

Blueprint: [`blueprints/aws-nextjs-rds.yaml`](../blueprints/aws-nextjs-rds.yaml)
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
2. Installs Node.js (`node_version`, default 22.11.0) from nodejs.org and enables corepack for pnpm/yarn.
3. Copies the built-in demo app, or `git clone`s `app_repo_url` at `app_git_ref`.
4. Waits for the database URL parameter (RDS is created in parallel), downloads the RDS CA bundle and writes `/etc/nextjs/app.env` (`DATABASE_URL`, `PORT`, `APP_URL`, `NODE_EXTRA_CA_CERTS`, plus `app_extra_env`).
5. Runs install → build → optional migrate. The package manager is detected from the lockfile; each step can be overridden.
6. Starts a `nextjs` systemd service on port 80, run as an unprivileged user with `CAP_NET_BIND_SERVICE`.

## Demo app

[`demo-app/`](../terraform/aws-nextjs-rds/demo-app/) is a Next.js 15 App Router app written in plain JS with `pg` as its only extra dependency. Each page view inserts a row into a `visits` table and shows the running count, the PostgreSQL version and whether the connection uses TLS. `/api/health` returns 200 only when a query to RDS succeeds; the Terraform health check polls this endpoint.

## Deploying a different Next.js project

Set `app_repo_url` (and `app_git_ref`) at launch. Most real projects also need extra env vars, such as auth secrets, and a migration step. These exist as module variables but aren't exposed in the blueprint yet:

```yaml
- app_subdir: apps/web                        # monorepos
- app_migrate_command: npx prisma migrate deploy
- app_extra_env: '{ "AUTH_SECRET": "{{ .params.app_auth_secret }}" }'
- health_check_path: /                        # defaults to / for custom repos
```

`APP_URL` (`http://<public-ip>`) is already present at build and runtime, which suits `NEXTAUTH_URL`-style settings.

## Known trade-offs

- **The health check runs from the Torque agent.** `allowed_cidr` must include the agent's egress IP; the default `0.0.0.0/0` does.
- **The health check also runs on destroy.** Terraform re-reads data sources on destroy, so if the app is dead at teardown the destroy retries for `health_check_timeout_minutes` and then fails. Set `wait_for_app = false` for environments you expect to break.
- **Plain HTTP on a public IP.** There's no ALB, TLS certificate or DNS, which is acceptable for a short-lived test.
- **`app_extra_env` values are sourced by bash during the build.** Avoid spaces, `$` or quotes in them.

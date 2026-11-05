#!/bin/bash
# First-boot provisioning for the Next.js EC2 instance (run by cloud-init).
#
#   1. swap file on small instances so 'next build' doesn't OOM
#   2. Node.js from nodejs.org (+ corepack for pnpm/yarn)
#   3. app source: built-in demo app, or a git clone
#   4. wait for the DATABASE_URL parameter (RDS is created in parallel)
#   5. install, build, optional migrate
#   6. systemd unit 'nextjs' on APP_PORT (+ optional 'nextjs-backend')
#
# Log: /var/log/nextjs-bootstrap.log
# Runtime: journalctl -u nextjs   (and -u nextjs-backend if configured)
set -euo pipefail
exec > >(tee -a /var/log/nextjs-bootstrap.log) 2>&1

log() { echo "[bootstrap $(date -u +%H:%M:%S)] $*"; }

CONF=/etc/nextjs/bootstrap.conf
cfg() { sed -n "s/^$1=//p" "$CONF" | base64 -d; }

AWS_REGION=$(cfg AWS_REGION)
DB_URL_PARAM=$(cfg DB_URL_PARAM)
NODE_VERSION=$(cfg NODE_VERSION)
APP_REPO_URL=$(cfg APP_REPO_URL)
APP_GIT_REF=$(cfg APP_GIT_REF)
APP_SUBDIR=$(cfg APP_SUBDIR)
APP_INSTALL_CMD=$(cfg APP_INSTALL_CMD)
APP_BUILD_CMD=$(cfg APP_BUILD_CMD)
APP_MIGRATE_CMD=$(cfg APP_MIGRATE_CMD)
APP_START_CMD=$(cfg APP_START_CMD)
APP_BACKEND_CMD=$(cfg APP_BACKEND_CMD)
APP_PORT=$(cfg APP_PORT)
APP_EXTRA_ENV=$(cfg APP_EXTRA_ENV)

APP_USER=nextjs
SRC_DIR=/srv/app
ENV_FILE=/etc/nextjs/app.env

# --- 1. swap ---------------------------------------------------------------
mem_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
if [ "$mem_kb" -lt 3000000 ] && [ ! -f /swapfile ]; then
  log "Adding 2 GiB swap (${mem_kb} kB RAM)"
  dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# --- 2. packages + Node.js -------------------------------------------------
log "Installing OS packages"
dnf install -y -q git tar xz

log "Installing Node.js v${NODE_VERSION}"
curl -fsSL --retry 5 "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" -o /tmp/node.tar.xz
mkdir -p /opt/node
tar -xJf /tmp/node.tar.xz -C /opt/node --strip-components=1
rm -f /tmp/node.tar.xz
ln -sf /opt/node/bin/node /opt/node/bin/npm /opt/node/bin/npx /usr/local/bin/
if [ -x /opt/node/bin/corepack ]; then
  ln -sf /opt/node/bin/corepack /usr/local/bin/
  corepack enable --install-directory /usr/local/bin
fi
node --version

# --- 3. app source ---------------------------------------------------------
id "$APP_USER" >/dev/null 2>&1 || useradd --system --create-home --shell /bin/bash "$APP_USER"

rm -rf "$SRC_DIR"
if [ -n "$APP_REPO_URL" ]; then
  log "Cloning ${APP_REPO_URL} @ ${APP_GIT_REF}"
  git clone --depth 1 --branch "$APP_GIT_REF" "$APP_REPO_URL" "$SRC_DIR"
else
  log "Using built-in demo app"
  cp -r /opt/nextjs/demo-app "$SRC_DIR"
fi
chown -R "$APP_USER:$APP_USER" "$SRC_DIR"
APP_DIR="$SRC_DIR${APP_SUBDIR:+/$APP_SUBDIR}"

# --- 4. database URL + RDS CA ----------------------------------------------
log "Downloading RDS CA bundle"
curl -fsSL --retry 5 https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem -o /etc/nextjs/rds-ca.pem

log "Waiting for ${DB_URL_PARAM} (RDS is still provisioning on first launch)"
DATABASE_URL=""
for _ in $(seq 1 120); do
  if DATABASE_URL=$(aws ssm get-parameter --region "$AWS_REGION" --name "$DB_URL_PARAM" \
      --with-decryption --query Parameter.Value --output text 2>/dev/null); then
    break
  fi
  sleep 15
done
[ -n "$DATABASE_URL" ] || { log "Timed out waiting for ${DB_URL_PARAM}"; exit 1; }

imds_token=$(curl -fsS -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 300')
PUBLIC_IP=$(curl -fsS -H "X-aws-ec2-metadata-token: ${imds_token}" http://169.254.169.254/latest/meta-data/public-ipv4)
if [ "$APP_PORT" = "80" ]; then APP_URL="http://${PUBLIC_IP}"; else APP_URL="http://${PUBLIC_IP}:${APP_PORT}"; fi

# Apps that call 'new pg.Pool()' with no config read the libpq-style PG*
# variables instead of DATABASE_URL, so export both forms.
pg_env=$(node -e '
  const u = new URL(process.argv[1]);
  console.log(`PGHOST=${u.hostname}\nPGPORT=${u.port || 5432}\nPGUSER=${decodeURIComponent(u.username)}`);
  console.log(`PGPASSWORD=${decodeURIComponent(u.password)}\nPGDATABASE=${u.pathname.slice(1)}\nPGSSLMODE=require`);
' "$DATABASE_URL")

# Per-instance random secret apps can use for session signing etc.
APP_SECRET=$(node -e 'console.log(require("crypto").randomBytes(32).toString("hex"))')

# Sourced by every step script (install/build/start), so later lines can
# reference earlier ones with bare $NAME (e.g. CORS_ORIGIN=$APP_URL in
# app_extra_env). NODE_ENV is deliberately absent: 'npm install' with
# NODE_ENV=production skips the devDependencies most builds need; the
# 'nextjs' unit sets it.
{
  echo "PORT=${APP_PORT}"
  echo "HOSTNAME=0.0.0.0"
  echo "APP_URL=${APP_URL}"
  echo "APP_SECRET=${APP_SECRET}"
  echo "DATABASE_URL=${DATABASE_URL}"
  printf '%s\n' "$pg_env"
  echo "NODE_EXTRA_CA_CERTS=/etc/nextjs/rds-ca.pem"
  echo "NEXT_TELEMETRY_DISABLED=1"
  echo "COREPACK_ENABLE_DOWNLOAD_PROMPT=0"
  if [ -n "$APP_EXTRA_ENV" ]; then printf '%s\n' "$APP_EXTRA_ENV"; fi
} > "$ENV_FILE"
chown "root:$APP_USER" "$ENV_FILE"
chmod 640 "$ENV_FILE"

# --- 5. install / build / migrate ------------------------------------------
pm=npm
if [ -f "$APP_DIR/pnpm-lock.yaml" ]; then
  pm=pnpm; default_install="pnpm install --frozen-lockfile"
elif [ -f "$APP_DIR/yarn.lock" ]; then
  pm=yarn; default_install="yarn install"
elif [ -f "$APP_DIR/package-lock.json" ]; then
  default_install="npm ci"
else
  default_install="npm install --no-audit --no-fund"
fi
APP_INSTALL_CMD=${APP_INSTALL_CMD:-$default_install}
APP_BUILD_CMD=${APP_BUILD_CMD:-"$pm run build"}
APP_START_CMD=${APP_START_CMD:-"$pm run start"}

# Commands go into small scripts so user-supplied strings never need quoting.
write_step() {
  printf '#!/bin/bash\nset -euo pipefail\nset -a; . %s; set +a\ncd %q\n%s\n' "$ENV_FILE" "$APP_DIR" "$2" > "/etc/nextjs/$1.sh"
  chmod 755 "/etc/nextjs/$1.sh"
}
write_step install "$APP_INSTALL_CMD"
write_step build "$APP_BUILD_CMD"
# No 'exec': commands like 'PORT=3001 pnpm start' must stay valid. systemd
# stops the whole cgroup, so the extra bash parent is harmless.
write_step start "$APP_START_CMD"
if [ -n "$APP_BACKEND_CMD" ]; then write_step backend "$APP_BACKEND_CMD"; fi
if [ -n "$APP_MIGRATE_CMD" ]; then write_step migrate "$APP_MIGRATE_CMD"; fi

# runuser keeps root's HOME, which would point npm/corepack caches at /root.
run_as_app() { runuser -u "$APP_USER" -- env HOME="/home/$APP_USER" PATH="/usr/local/bin:/usr/bin:/bin" "$@"; }

log "Install: ${APP_INSTALL_CMD}"
run_as_app /etc/nextjs/install.sh
log "Build: ${APP_BUILD_CMD}"
run_as_app NODE_ENV=production /etc/nextjs/build.sh
if [ -n "$APP_MIGRATE_CMD" ]; then
  log "Migrate: ${APP_MIGRATE_CMD}"
  run_as_app /etc/nextjs/migrate.sh
fi

# --- 6. service ------------------------------------------------------------
cat > /etc/systemd/system/nextjs.service <<EOF
[Unit]
Description=Next.js app
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${APP_USER}
WorkingDirectory=${APP_DIR}
Environment=NODE_ENV=production
ExecStart=/etc/nextjs/start.sh
Restart=always
RestartSec=5
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

# The backend unit deliberately sets no NODE_ENV; put it in the command if
# the backend wants it (some, like chessu, only send cookies over HTTPS in
# production mode).
if [ -n "$APP_BACKEND_CMD" ]; then
  cat > /etc/systemd/system/nextjs-backend.service <<EOF
[Unit]
Description=Next.js app backend
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${APP_USER}
WorkingDirectory=${APP_DIR}
ExecStart=/etc/nextjs/backend.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
fi

systemctl daemon-reload
if [ -n "$APP_BACKEND_CMD" ]; then systemctl enable --now nextjs-backend; fi
systemctl enable --now nextjs
log "Done. App starting on ${APP_URL}"

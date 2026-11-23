#!/bin/bash
# Grovs on Railway: one container runs the API, the five Sidekiq queues and a Host-rewriting gateway, because Railway gives a service
# one volume and the local uploads must be shared by all of them.
#   - the volume is mounted root-owned, so it is chowned to the grovs user (1000) before everything drops to that user;
#   - Grovs routes on the first label of the Host header (api., sdk., ...); Railway gives one generated domain per service, so the
#     gateway on :8080 sets that label itself (see Caddyfile);
#   - every address is derived from this service's own public domain, so the deploy form has nothing to fill in.
set -eu
: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is not set}"
: "${REDIS_PASSWORD:?REDIS_PASSWORD is not set}"
: "${CLICKHOUSE_PASSWORD:?CLICKHOUSE_PASSWORD is not set}"
: "${RAILWAY_PUBLIC_DOMAIN:?RAILWAY_PUBLIC_DOMAIN is not set}"

if [ "$(id -u)" != 0 ]; then
  echo "[grovs] ERROR: must start as root (set RAILWAY_RUN_UID=0); uid is $(id -u)" >&2
  exit 1
fi

DATA=/app/storage
mkdir -p "$DATA" /tmp/caddy-data /tmp/caddy-config /app/tmp /app/log
chown -R 1000:1000 "$DATA" /tmp/caddy-data /tmp/caddy-config /app/tmp /app/log
echo "[grovs] volume $DATA owner=$(stat -c %u:%g "$DATA") writable=$(setpriv --reuid=1000 --regid=1000 --init-groups sh -c "test -w $DATA && echo yes || echo NO")"

# Railway resolves the dashboard address only once the dashboard service exists. A template deploy creates all services together, so
# it is set there; the fallback keeps a project that is built service by service from crash-looping on its first deploy.
if [ -z "${REACT_HOST:-}" ]; then
  echo "[grovs] WARN: REACT_HOST is empty (dashboard service not created yet); the dashboard origin is unset until the next deploy" >&2
  REACT_HOST="dashboard.invalid"
fi
export REACT_HOST
export SERVER_HOST="$RAILWAY_PUBLIC_DOMAIN"
export GATEWAY_HOST="$RAILWAY_PUBLIC_DOMAIN"
export DOMAIN_LIVE="$SERVER_HOST"
export DOMAIN_TEST="test.$SERVER_HOST"
export PREVIEW_BASE_URL="https://preview.$SERVER_HOST"
export MCP_CONSENT_URL="https://$REACT_HOST/mcp/authorize"
export S3_ASSET_PREFIX="https://$SERVER_HOST"
export DEFAULT_LOGO_URL="https://$SERVER_HOST/assets/logo-square-black.png"
export DEFAULT_SOCIAL_PREVIEW_URL="https://$SERVER_HOST/assets/social-media-placeholder.jpg"
export DATABASE_URL="postgres://grovs:${POSTGRES_PASSWORD}@${POSTGRES_HOST:-db.railway.internal}:5432/grovs_production"
export REDIS_URL="redis://default:${REDIS_PASSWORD}@${REDIS_HOST:-redis.railway.internal}:6379/0"
export CLICKHOUSE_URL="http://grovs:${CLICKHOUSE_PASSWORD}@${CLICKHOUSE_HOST:-clickhouse.railway.internal}:8123"
export MAILER_FROM="Grovs <noreply@$SERVER_HOST>"
export SMTP_DOMAIN="$SERVER_HOST"

run() { setpriv --reuid=1000 --regid=1000 --init-groups "$@"; }

# The gateway answers /healthz by itself, so the deploy turns healthy while the first migration still runs.
run caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &
CADDY=$!

cd /app
n=0
until run bash -c 'bin/rails db:prepare && bin/rails db:seed && bin/rails clickhouse:setup'; do
  n=$((n + 1))
  if [ "$n" -ge 40 ]; then echo "[grovs] ERROR: migrations still failing after $n tries" >&2; exit 1; fi
  echo "[grovs] migrate attempt $n failed; databases may still be starting, retrying in 10s"
  sleep 10
done
echo "[grovs] migrations done, starting the API and the workers"

run bundle exec puma -b tcp://0.0.0.0:3000 &
for q in scheduler worker batch maintenance device_updates; do
  run bundle exec sidekiq -C "config/sidekiq_${q}.yml" &
done

# One process dying takes the container down, so Railway restarts the whole set rather than leave a silent half.
wait -n
echo "[grovs] a process exited; stopping the container" >&2
exit 1

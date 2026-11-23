# upstream: grovs-io/backend
FROM ghcr.io/grovs-io/backend:3.0.1@sha256:b4582c9abfd5843c396718841026fc7b2e0af887de196fc7cab6c9ef80e135db

# Grovs 3.0.1 Community Edition. Upstream runs the API, the migrate step and two worker containers around a shared volume; on Railway one
# service owns one volume, so this image runs migrate, puma, five sidekiq processes and a small Host-rewriting gateway together and
# keeps uploads on the local volume. No S3 bucket is needed.
USER root
# upstream: none Caddy is the gateway binary only, copied from the official alpine image (static Go build)
COPY --from=caddy:2-alpine@sha256:003a97808e781aa9f7e75cc2f43d34d461099031faf5e20faefb9f61126836f0 /usr/bin/caddy /usr/local/bin/caddy
COPY Caddyfile /etc/caddy/Caddyfile
COPY --chmod=755 railway-boot.sh /usr/local/bin/railway-boot.sh

ENV RAILS_ENV=production \
    RAILS_LOG_TO_STDOUT=true \
    RAILS_SERVE_STATIC_FILES=true \
    GROVS_SELF_HOSTED=true \
    ACTIVE_STORAGE_SERVICE=local \
    SERVER_HOST_PROTOCOL=https:// \
    REACT_HOST_PROTOCOL=https:// \
    POSTGRES_USER=grovs \
    POSTGRES_DB=grovs_production \
    CLICKHOUSE_DATABASE=grovs_production \
    CLICKHOUSE_WRITE_ENABLED=true \
    CLICKHOUSE_READ_ENABLED=true \
    CLICKHOUSE_PRIMARY=true \
    CLICKHOUSE_ANALYTICS_ROLLUPS_READ_ENABLED=true \
    CLICKHOUSE_ATTRIBUTION_READ_ENABLED=true \
    CLICKHOUSE_LINK_DIMENSIONS_READ_ENABLED=true \
    REVENUE_READS_FROM_LEDGER=true \
    CLICKHOUSE_ROLLUP_FAST_LANE=true \
    DASHBOARD_CACHE_TTL_SECONDS=60 \
    PG_SHADOW_WRITES=false \
    PUBLIC_GO_PROJECT_IDENTIFIER=go-self-hosted \
    WEB_CONCURRENCY=1 \
    RAILS_MAX_THREADS=5 \
    RAILS_DB_POOL=10 \
    SIDEKIQ_EVENTS_CONCURRENCY=10 \
    XDG_DATA_HOME=/tmp/caddy-data \
    XDG_CONFIG_HOME=/tmp/caddy-config

# The entrypoint runs as root only to own the Railway volume, then drops to the grovs user.
ENTRYPOINT ["/usr/local/bin/railway-boot.sh"]

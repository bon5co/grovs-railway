#!/bin/sh
set -eu
: "${REDIS_PASSWORD:?REDIS_PASSWORD is not set}"
# Railway mounts the volume root-owned; chown it, then let the stock entrypoint drop to the redis user.
# noeviction is what Grovs' job queues need (upstream's compose passes the same flag); bind covers IPv4 and IPv6 for the private network.
chown -R redis:redis /data
exec docker-entrypoint.sh redis-server --requirepass "$REDIS_PASSWORD" --appendonly yes --dir /data --maxmemory-policy noeviction --bind "* -::*"

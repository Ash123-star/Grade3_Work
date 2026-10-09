#!/bin/sh
set -eu
: "${REDIS_PASSWORD:?REDIS_PASSWORD is required}"
export REDISCLI_AUTH="$REDIS_PASSWORD"
exec redis-cli --no-auth-warning "$@"

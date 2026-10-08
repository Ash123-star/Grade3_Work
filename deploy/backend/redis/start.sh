#!/bin/sh
set -eu
: "${REDIS_PASSWORD:?REDIS_PASSWORD is required}"
case "$REDIS_PASSWORD" in
  *[!a-zA-Z0-9_-]*|'') echo 'REDIS_PASSWORD must contain only letters, digits, underscore or hyphen' >&2; exit 1 ;;
esac
umask 077
config_dir=/run/workpanel-redis
mkdir -p "$config_dir"
cp /opt/redis/redis.conf "$config_dir/redis.conf"
printf '\nrequirepass %s\n' "$REDIS_PASSWORD" >> "$config_dir/redis.conf"
if [ "$(id -u)" = 0 ]; then chown -R redis:redis "$config_dir"; fi
exec /usr/local/bin/docker-entrypoint.sh redis-server "$config_dir/redis.conf"

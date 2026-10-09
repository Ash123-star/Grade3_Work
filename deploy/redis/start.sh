#!/bin/sh
set -eu
: "${REDIS_PASSWORD:?REDIS_PASSWORD is required}"
# 使用单行令牌防止 Redis 配置注入；脚本生成十六进制随机密码。
case "$REDIS_PASSWORD" in
  *[!a-zA-Z0-9_-]*|'') echo 'REDIS_PASSWORD must be an alphanumeric token (underscore and hyphen allowed)' >&2; exit 1 ;;
esac
umask 077
config_dir=/run/collaboration-redis
mkdir -p "$config_dir"
cp /opt/redis/redis.conf "$config_dir/redis.conf"
printf '\nrequirepass %s\n' "$REDIS_PASSWORD" >> "$config_dir/redis.conf"
if [ "$(id -u)" = 0 ]; then chown -R redis:redis "$config_dir"; fi
if [ "${COMBINED_DATA_RUNTIME:-0}" = 1 ]; then
    exec gosu redis redis-server "$config_dir/redis.conf"
fi
exec /usr/local/bin/docker-entrypoint.sh redis-server "$config_dir/redis.conf"

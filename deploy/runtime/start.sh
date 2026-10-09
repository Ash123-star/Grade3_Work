#!/bin/sh
set -eu
postgres_pid=''
redis_pid=''
stop_children() {
    trap '' TERM INT HUP
    if [ -n "$postgres_pid" ]; then kill -TERM "$postgres_pid" 2>/dev/null || true; fi
    if [ -n "$redis_pid" ]; then kill -TERM "$redis_pid" 2>/dev/null || true; fi
    if [ -n "$postgres_pid" ]; then wait "$postgres_pid" 2>/dev/null || true; fi
    if [ -n "$redis_pid" ]; then wait "$redis_pid" 2>/dev/null || true; fi
}
trap 'stop_children; exit 0' TERM INT HUP
mkdir -p /data
chown -R redis:redis /data
/usr/local/bin/docker-entrypoint.sh postgres &
postgres_pid=$!
/bin/sh /opt/redis/start.sh &
redis_pid=$!
while kill -0 "$postgres_pid" 2>/dev/null && kill -0 "$redis_pid" 2>/dev/null; do
    sleep 1 &
    wait $! || true
done
echo 'A database process exited; stopping the other database.' >&2
stop_children
exit 1

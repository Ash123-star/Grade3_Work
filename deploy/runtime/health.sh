#!/bin/sh
set -eu
pg_isready -q -U "$POSTGRES_USER" -d "$POSTGRES_DB"
test "$(/bin/sh /opt/redis/auth-cli.sh ping)" = PONG

#!/bin/sh
set -eu
reply=$(curl --silent --show-error --fail --max-time 3 --user "neo4j:$NEO4J_PASSWORD" \
    --header 'Content-Type: application/json' --data '{"statements":[{"statement":"RETURN 1"}]}' \
    http://127.0.0.1:7474/db/neo4j/tx/commit)
case "$reply" in *'"errors":[]'*) exit 0 ;; *) exit 1 ;; esac

#!/bin/sh
set -eu
: "${NEO4J_PASSWORD:?NEO4J_PASSWORD required}"
if [ "${#NEO4J_PASSWORD}" -lt 16 ]; then echo 'Neo4j password must have at least 16 characters.' >&2; exit 1; fi
mkdir -p /var/lib/neo4j/data /var/lib/neo4j/logs /var/lib/neo4j/run
cat > /var/lib/neo4j/conf/neo4j.conf <<'EOF'
server.directories.data=/var/lib/neo4j/data
server.directories.logs=/var/lib/neo4j/logs
server.directories.run=/var/lib/neo4j/run
server.default_listen_address=0.0.0.0
server.bolt.enabled=true
server.bolt.listen_address=:7687
server.http.enabled=true
server.http.listen_address=:7474
server.https.enabled=false
server.memory.heap.initial_size=128m
server.memory.heap.max_size=256m
server.memory.pagecache.size=128m
dbms.security.auth_enabled=true
dbms.security.procedures.unrestricted=
EOF
chown -R neo4j:neo4j /var/lib/neo4j
if [ ! -f /var/lib/neo4j/data/dbms/auth.ini ] && [ ! -d /var/lib/neo4j/data/databases/system ]; then
    gosu neo4j /var/lib/neo4j/bin/neo4j-admin dbms set-initial-password "$NEO4J_PASSWORD" >/dev/null
fi
cd /var/lib/neo4j
exec gosu neo4j /var/lib/neo4j/bin/neo4j console

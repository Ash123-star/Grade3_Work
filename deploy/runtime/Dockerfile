FROM redis:7 AS redis-runtime
FROM neo4j:5.26-community AS neo4j-runtime
FROM eclipse-temurin:21-jre-jammy AS java-runtime
FROM postgres:16
COPY --from=redis-runtime /usr/local/bin/redis-server /usr/local/bin/redis-server
COPY --from=redis-runtime /usr/local/bin/redis-cli /usr/local/bin/redis-cli
COPY --from=neo4j-runtime /var/lib/neo4j /var/lib/neo4j
COPY --from=java-runtime /opt/java/openjdk /opt/java/openjdk
RUN groupadd --system redis && useradd --system --gid redis --home-dir /data redis \
    && groupadd --system neo4j && useradd --system --gid neo4j --home-dir /var/lib/neo4j neo4j \
    && apt-get update && apt-get install -y --no-install-recommends curl libfreetype6 fontconfig \
    && rm -rf /var/lib/apt/lists/* \
    && redis-server --version && redis-cli --version
ENV JAVA_HOME=/opt/java/openjdk
ENV PATH=/opt/java/openjdk/bin:$PATH
RUN for dir in data logs conf run; do \
      if [ -L /var/lib/neo4j/$dir ]; then rm /var/lib/neo4j/$dir; fi; \
      mkdir -p /var/lib/neo4j/$dir; \
    done
COPY runtime/start.sh /opt/runtime/start.sh
COPY runtime/health.sh /opt/runtime/health.sh
COPY runtime/neo4j-start.sh /opt/runtime/neo4j-start.sh
COPY runtime/neo4j-health.sh /opt/runtime/neo4j-health.sh
ENV COMBINED_DATA_RUNTIME=1
ENTRYPOINT ["/bin/sh", "/opt/runtime/start.sh"]
CMD []

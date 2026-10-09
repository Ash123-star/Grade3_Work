FROM redis:7 AS redis-runtime
FROM postgres:16
COPY --from=redis-runtime /usr/local/bin/redis-server /usr/local/bin/redis-server
COPY --from=redis-runtime /usr/local/bin/redis-cli /usr/local/bin/redis-cli
RUN groupadd --system redis && useradd --system --gid redis --home-dir /data redis \
    && redis-server --version && redis-cli --version
COPY runtime/start.sh /opt/runtime/start.sh
COPY runtime/health.sh /opt/runtime/health.sh
ENV COMBINED_DATA_RUNTIME=1
ENTRYPOINT ["/bin/sh", "/opt/runtime/start.sh"]
CMD []

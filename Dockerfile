FROM alpine:3.20

WORKDIR /app

RUN apk add --no-cache ca-certificates libstdc++ wget file \
    && addgroup -S soonlink \
    && adduser -S -G soonlink soonlink

COPY dist/soonlnk /app/soonlnk
COPY dist/config /app/config
COPY dist/web /app/web
COPY dist/docker/entrypoint.sh /app/docker/entrypoint.sh

RUN chmod +x /app/soonlnk /app/docker/entrypoint.sh \
    && mkdir -p /app/runtime/config /app/runtime/tmp /app/runtime/logs /app/runtime/cache/relay /app/data \
    && chown -R soonlink:soonlink /app

USER soonlink

EXPOSE 8081

ENTRYPOINT ["/app/docker/entrypoint.sh"]

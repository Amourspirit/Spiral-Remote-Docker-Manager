FROM curlimages/curl:latest

USER root

# tunnel_route.sh uses bash and jq.
RUN apk add --no-cache bash jq

WORKDIR /app

COPY src/tunnel_route.sh /app/tunnel_route.sh
COPY src/entrypoint.sh /app/entrypoint.sh

RUN chmod +x /app/tunnel_route.sh /app/entrypoint.sh

STOPSIGNAL SIGTERM

ENTRYPOINT ["/app/entrypoint.sh"]

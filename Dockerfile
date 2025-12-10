FROM caddy:2.8-alpine

WORKDIR /app

RUN apk add --no-cache \
    bash curl ca-certificates tzdata coreutils su-exec \
 && update-ca-certificates

COPY index.html /srv/index.html
COPY Caddyfile /etc/caddy/Caddyfile
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh \
 && adduser -D -u 1000 appuser \
 && chown -R 1000:1000 /app

ENV WSPORT=7860
# 关键：不要在这里 USER 1000，让入口先 root
CMD ["bash", "/app/start.sh"]

# Caddy with the Cloudflare DNS-01 plugin (ADR 0018). Both stages track the
# caddy:2 line; Renovate pins and bumps them from M7.
FROM caddy:2-builder AS builder
RUN xcaddy build --with github.com/caddy-dns/cloudflare

FROM caddy:2
COPY --from=builder /usr/bin/caddy /usr/bin/caddy

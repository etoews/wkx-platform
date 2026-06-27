# Same Compose model on AWS and on-prem, differing only by profile flags

Status: accepted

The cloud host and the home server run the same `platform/compose.yml` and the same app Compose definitions. The differences between targets are expressed as Compose profile flags, not as separate stacks: on-prem has no Cloudflare DNS-01 and uses a LAN-only Caddy listener, while AWS takes the full Cloudflare path. One mental model spans both homes. The trade-off is that every change must keep both profiles working. See ADR-0001 (single-instance Compose) and ADR-0004 (the Cloudflare-specific path on-prem omits).

_Source: design spec §8.1, §1._

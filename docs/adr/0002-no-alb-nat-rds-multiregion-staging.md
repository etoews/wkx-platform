# No ALB, NAT Gateway, RDS, multi-region, or separate staging account

Status: accepted

The platform deliberately does not build five things that a default AWS design would reach for:

- **No ALB.** Caddy on the box does TLS and routing. ALB alone is ~USD $16/mo.
- **No NAT Gateway.** Public subnet only; outbound goes direct via the box's public IP. NAT GW is ~USD $32/mo.
- **No RDS.** Databases run as Compose containers. The smallest RDS is ~USD $15/mo plus storage.
- **No multi-region or DR.** Single region, with backup-driven recovery to a fresh instance.
- **No separate staging account.** The explicit `env` dimension (see ADR-0006) is the seam for staging-like behaviour without dedicated infrastructure.

Each was costed and rejected against the NZD $50/mo budget. Adding any of them is a design change, not an implementation detail.

_Source: design spec §8.3, §2; CLAUDE.md Invariant 6._

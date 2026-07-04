# One wildcard certificate, plain host-block snippets

Status: accepted

Caddy issues a single DNS-01 wildcard certificate for `*.wingkongexchange.dev` (via the Cloudflare plugin), and project Caddy snippets stay plain host blocks that ride it, enabled by the `auto_https prefer_wildcard` global option (default behaviour from Caddy 2.10). This preserves the snippet contract in CONTEXT.md, "one Caddy host block per project", while every subdomain, including future M11 preview envs, shares one certificate.

Two alternatives were rejected. Per-hostname certificates (each snippet carrying its own `tls dns cloudflare`) would repeat the tls stanza in every snippet and churn Let's Encrypt issuance on every preview env deploy. A single wildcard site block with matcher-plus-handle snippets works on any Caddy version but changes the snippet contract to a matcher/handle pair, and handle ordering inside one site becomes a failure mode as projects multiply; it remains the recorded fallback if `prefer_wildcard` regresses. The contract ships in every `wkx-*` repo from M6 on, which is what makes this hard to reverse.

_Source: M3 design spec (2026-07-05) §2, §4.2._

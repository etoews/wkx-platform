# One wildcard certificate, plain host-block snippets

Status: accepted

Caddy issues a single DNS-01 wildcard certificate for `*.wingkongexchange.dev` (via the Cloudflare plugin), and project Caddy snippets stay plain host blocks that ride it. Wildcard reuse is Caddy's default behaviour from 2.10: when the DNS challenge is enabled on the wildcard site block, covered subdomain site blocks use the wildcard certificate rather than obtaining their own. This preserves the snippet contract in CONTEXT.md, "one Caddy host block per project", while every subdomain, including future M11 preview envs, shares one certificate.

M3 execution note (2026-07-05): the design named the `auto_https prefer_wildcard` global option as the enabling flag. The Task 1 decision gate found the shipped image (caddy:2, v2.11.4) rejects that value, and the current Caddy docs confirm the flag was removed once the behaviour became the default; subdomains only get separate certificates if explicitly forced (`force_automate`). The shipped Caddyfile therefore carries no `auto_https` option at all. The contract this ADR records is unchanged.

Two alternatives were rejected. Per-hostname certificates (each snippet carrying its own `tls dns cloudflare`) would repeat the tls stanza in every snippet and churn Let's Encrypt issuance on every preview env deploy. A single wildcard site block with matcher-plus-handle snippets works on any Caddy version but changes the snippet contract to a matcher/handle pair, and handle ordering inside one site becomes a failure mode as projects multiply; it remains the recorded fallback if default wildcard reuse regresses. The contract ships in every `wkx-*` repo from M6 on, which is what makes this hard to reverse.

_Source: M3 design spec (2026-07-05) §2, §4.2._

# Cloudflare for DNS, proxy, WAF, and TLS

Status: accepted

DNS, the CDN/proxy, DDoS protection, the WAF, and edge TLS all run on Cloudflare's free tier, in front of the AWS origin. The free tier covers all of it at no cost, a large security and availability multiplier for personal-scale traffic. The trade-off is a second IaC provider to manage (the Cloudflare Terraform provider) alongside AWS; the friction is worth it at $0. See ADR-0004 for how the origin is locked to Cloudflare's IP ranges, and ADR-0009 for the single-IaC-tool stance.

_Source: design spec §8.1, §8.2._

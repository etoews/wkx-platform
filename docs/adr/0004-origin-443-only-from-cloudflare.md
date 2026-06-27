# Origin accepts 443 only from Cloudflare, no port 80

Status: accepted

The origin security group admits port 443 only from Cloudflare's published IPv4 and IPv6 ranges, pulled via a Terraform data source so the list stays current. It opens no port 80. Cloudflare reaches the origin over HTTPS in Full (strict) mode, Caddy issues a wildcard certificate via DNS-01, and the HTTP-to-HTTPS redirect happens at Cloudflare's edge. This drops direct-to-origin attacks at the security group and avoids ALB plus ACM costs.

The trade-offs: certificate renewal lives on the box (Let's Encrypt's 30-day buffer is forgiving, with a CloudWatch alarm on cert age), and the security group's correctness depends on an accurate Cloudflare IP list (refreshed as part of monthly maintenance).

_Source: design spec §8.1, §8.2; CLAUDE.md Invariant 3._

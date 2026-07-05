# hello: the M3 smoke-test Service. Proxied (orange cloud): browsers reach
# Cloudflare's edge; only the edge reaches the origin (ADRs 0004, 0008).
# ttl = 1 means "auto", required for proxied records.
resource "cloudflare_dns_record" "hello_a" {
  zone_id = cloudflare_zone.apps.id
  name    = "hello"
  type    = "A"
  content = var.host_public_ip
  proxied = true
  ttl     = 1
}

resource "cloudflare_dns_record" "hello_aaaa" {
  zone_id = cloudflare_zone.apps.id
  name    = "hello"
  type    = "AAAA"
  content = var.host_ipv6_address
  proxied = true
  ttl     = 1
}

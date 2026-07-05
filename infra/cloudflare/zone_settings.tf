# Zone security posture, Terraform-managed rather than console defaults.
# Full (strict): the edge validates the origin's Let's Encrypt cert.
resource "cloudflare_zone_setting" "ssl" {
  zone_id    = cloudflare_zone.apps.id
  setting_id = "ssl"
  value      = "strict"
}

# The HTTP to HTTPS redirect happens at the edge; origin port 80 stays
# closed (ADR 0004).
resource "cloudflare_zone_setting" "always_use_https" {
  zone_id    = cloudflare_zone.apps.id
  setting_id = "always_use_https"
  value      = "on"
}

resource "cloudflare_zone_setting" "min_tls_version" {
  zone_id    = cloudflare_zone.apps.id
  setting_id = "min_tls_version"
  value      = "1.2"
}

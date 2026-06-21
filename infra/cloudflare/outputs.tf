output "zone_id" {
  description = "Cloudflare zone ID for the apps apex."
  value       = cloudflare_zone.apps.id
}

output "name_servers" {
  description = "Cloudflare nameservers assigned to the zone."
  value       = cloudflare_zone.apps.name_servers
}

output "dns_api_token" {
  description = "Zone-scoped DNS:Edit token for Caddy DNS-01 (M3)."
  value       = cloudflare_account_token.dns_edit.value
  sensitive   = true
}

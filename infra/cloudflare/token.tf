# Narrow zone-scoped token for Caddy's DNS-01 challenge (M3). Stored in state
# (encrypted bucket); moved to SSM in M5.
#
# Account-owned token (not a user token): the bootstrap credential is scoped to
# Account -> API Tokens -> Edit, so it can mint account tokens but not user
# tokens. An account-owned service credential is also the right model here.
#
# The permission group ID below is Cloudflare's stable, account-independent
# "DNS Write" group, verified against this account's token permission groups
# (GET /accounts/<id>/tokens/permission_groups). Scoped to the wkx.dev zone only.
resource "cloudflare_account_token" "dns_edit" {
  account_id = var.cloudflare_account_id
  name       = "wkx-caddy-dns01"

  policies = [{
    effect = "allow"
    permission_groups = [{
      id = "4755a26eedb94da69e1066d98aa820be" # "DNS Write"
    }]
    # v5 flattens the resources map to a JSON-encoded string.
    resources = jsonencode({
      "com.cloudflare.api.account.zone.${cloudflare_zone.apps.id}" = "*"
    })
  }]
}

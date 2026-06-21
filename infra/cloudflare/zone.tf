resource "cloudflare_zone" "apps" {
  account = {
    id = var.cloudflare_account_id
  }
  name = var.apps_apex
  type = "full"

  lifecycle {
    prevent_destroy = true # never let `destroy` remove the registered zone
  }
}

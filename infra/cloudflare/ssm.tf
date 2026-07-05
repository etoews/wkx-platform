# Delivers the DNS-01 token to the Host: rendered at deploy time into
# /srv/secrets/caddy/prod.env (M5 generalises this render). SecureString
# under the AWS-managed aws/ssm key; the wkx-host role reads /wkx/* only.
resource "aws_ssm_parameter" "caddy_cloudflare_token" {
  name  = "/wkx/caddy/prod/CLOUDFLARE_API_TOKEN"
  type  = "SecureString"
  value = cloudflare_account_token.dns_edit.value

  tags = {
    Name    = "/wkx/caddy/prod/CLOUDFLARE_API_TOKEN"
    Service = "caddy"
    Env     = "prod"
  }
}

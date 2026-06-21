# Cloudflare's published origin IP ranges (https://www.cloudflare.com/ips/).
# Pulled via the http data source so this root needs no Cloudflare provider/credential.
data "http" "cloudflare_ipv4" {
  url = "https://www.cloudflare.com/ips-v4"
}

data "http" "cloudflare_ipv6" {
  url = "https://www.cloudflare.com/ips-v6"
}

locals {
  cloudflare_ipv4_cidrs = [
    for c in split("\n", trimspace(data.http.cloudflare_ipv4.response_body)) : c if c != ""
  ]
  cloudflare_ipv6_cidrs = [
    for c in split("\n", trimspace(data.http.cloudflare_ipv6.response_body)) : c if c != ""
  ]
}

resource "aws_ec2_managed_prefix_list" "cloudflare_ipv4" {
  name           = "wkx-cloudflare-ipv4"
  address_family = "IPv4"
  max_entries    = 30 # Cloudflare publishes ~15; headroom avoids churn-driven replacement.

  dynamic "entry" {
    for_each = toset(local.cloudflare_ipv4_cidrs)
    content {
      cidr = entry.value
    }
  }

  tags = { Name = "wkx-cloudflare-ipv4" }
}

resource "aws_ec2_managed_prefix_list" "cloudflare_ipv6" {
  name           = "wkx-cloudflare-ipv6"
  address_family = "IPv6"
  max_entries    = 20 # Cloudflare publishes ~7; headroom.

  dynamic "entry" {
    for_each = toset(local.cloudflare_ipv6_cidrs)
    content {
      cidr = entry.value
    }
  }

  tags = { Name = "wkx-cloudflare-ipv6" }
}

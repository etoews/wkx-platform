# web: ingress only. 443 from Cloudflare prefix lists. No port 80, no port 22. No
# egress here (egress is owned by host_egress; multiple SGs on one ENI union their
# allows). Port 80 is intentionally not opened: Cloudflare reaches the origin over
# HTTPS in Full (strict) SSL mode, Caddy issues certs via DNS-01 (not HTTP-01), and
# the HTTP->HTTPS redirect happens at Cloudflare's edge. Origin port 80 would be
# pure attack surface.
resource "aws_security_group" "web" {
  name        = "wkx-web"
  description = "Ingress 443 from Cloudflare ranges only"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "wkx-web" }
}

resource "aws_vpc_security_group_ingress_rule" "web_https_ipv4" {
  security_group_id = aws_security_group.web.id
  description       = "HTTPS from Cloudflare IPv4"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = aws_ec2_managed_prefix_list.cloudflare_ipv4.id
}

resource "aws_vpc_security_group_ingress_rule" "web_https_ipv6" {
  security_group_id = aws_security_group.web.id
  description       = "HTTPS from Cloudflare IPv6"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = aws_ec2_managed_prefix_list.cloudflare_ipv6.id
}

# host_egress: all outbound, both families. No ingress.
resource "aws_security_group" "host_egress" {
  name        = "wkx-host-egress"
  description = "All outbound traffic"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "wkx-host-egress" }
}

resource "aws_vpc_security_group_egress_rule" "host_egress_ipv4" {
  security_group_id = aws_security_group.host_egress.id
  description       = "All outbound IPv4"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "host_egress_ipv6" {
  security_group_id = aws_security_group.host_egress.id
  description       = "All outbound IPv6"
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"
}

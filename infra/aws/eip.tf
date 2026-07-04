# Stable public IPv4 for the Host. M3's Cloudflare DNS records point here,
# so it must survive instance replacement; the association re-targets the
# replacement instance.
resource "aws_eip" "host" {
  domain = "vpc"
  tags   = { Name = "wkx-host" }
}

resource "aws_eip_association" "host" {
  allocation_id = aws_eip.host.id
  instance_id   = aws_instance.host.id
}

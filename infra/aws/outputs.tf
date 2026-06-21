output "vpc_id" {
  description = "Platform VPC ID."
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "Public subnet ID (the M2 host lands here)."
  value       = aws_subnet.public.id
}

output "cloudflare_ipv4_prefix_list_id" {
  description = "Managed prefix list of Cloudflare IPv4 ranges."
  value       = aws_ec2_managed_prefix_list.cloudflare_ipv4.id
}

output "cloudflare_ipv6_prefix_list_id" {
  description = "Managed prefix list of Cloudflare IPv6 ranges."
  value       = aws_ec2_managed_prefix_list.cloudflare_ipv6.id
}

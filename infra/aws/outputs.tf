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

output "web_sg_id" {
  description = "Security group: HTTPS (443) ingress from Cloudflare prefix lists only."
  value       = aws_security_group.web.id
}

output "host_egress_sg_id" {
  description = "Security group allowing all outbound."
  value       = aws_security_group.host_egress.id
}

output "instance_id" {
  description = "EC2 instance ID of the Host (SSM session target)."
  value       = aws_instance.host.id
}

output "host_public_ip" {
  description = "Elastic IP attached to the Host (M3 DNS records target this)."
  value       = aws_eip.host.public_ip
}

output "data_volume_id" {
  description = "EBS volume ID of the Data volume (/srv/data)."
  value       = aws_ebs_volume.data.id
}

output "instance_profile_name" {
  description = "IAM instance profile attached to the Host."
  value       = aws_iam_instance_profile.host.name
}

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

output "caddy_ecr_repository_url" {
  description = "ECR repository URL for the platform Caddy image."
  value       = module.caddy.repository_url
}

output "hello_ecr_repository_url" {
  description = "ECR repository URL for the hello image."
  value       = module.hello.repository_url
}

output "github_oidc_provider_arn" {
  description = "ARN of the account's GitHub Actions OIDC provider (the Federated principal every per-project CI role trusts)."
  value       = aws_iam_openid_connect_provider.github.arn
}

output "deploy_bucket_name" {
  description = "Name of the shared deploy bucket (ADR 0024); GitHub Actions uploads bundles here under deploy/<service>/<sha>/."
  value       = aws_s3_bucket.deploy.bucket
}

output "hello_ci_role_arn" {
  description = "ARN of the wkx-hello CI push/deploy role (assumed via OIDC from the repo's main ref)."
  value       = module.hello.ci_role_arn
}

output "host_ipv6_address" {
  description = "Pinned IPv6 address of the Host (M3 AAAA record targets this)."
  value       = one(aws_instance.host.ipv6_addresses)
}

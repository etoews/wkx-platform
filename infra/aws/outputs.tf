output "vpc_id" {
  description = "Platform VPC ID."
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "Public subnet ID (the M2 host lands here)."
  value       = aws_subnet.public.id
}

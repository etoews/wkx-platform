output "state_bucket_name" {
  description = "Name of the S3 bucket holding Terraform state. Use as -backend-config bucket value."
  value       = aws_s3_bucket.state.bucket
}

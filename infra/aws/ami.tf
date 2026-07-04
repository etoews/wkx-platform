# Canonical's published pointer to the latest stable Ubuntu 26.04 (Resolute)
# arm64 server AMI. Resolved at plan time; never hardcode an AMI ID. The
# instance ignores day-to-day drift of this value (see ec2.tf lifecycle):
# replacements pick up the then-current AMI, but a new AMI never causes a
# replacement by itself.
data "aws_ssm_parameter" "ubuntu_arm64" {
  name = "/aws/service/canonical/ubuntu/server/26.04/stable/current/arm64/hvm/ebs-gp3/ami-id"
}

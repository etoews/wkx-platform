locals {
  # Stable /dev/disk/by-id symlink for the Data volume, derived from the
  # volume ID with the dash removed. The kernel's nvme names (/dev/nvme1n1)
  # and the attachment's /dev/sdf are both unstable; this symlink is not.
  data_volume_device = "/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_${replace(aws_ebs_volume.data.id, "-", "")}"
}

# The Data volume: durable app data, independent of the instance lifecycle
# (ADR 0017). M10 snapshots target exactly this volume.
resource "aws_ebs_volume" "data" {
  availability_zone = aws_subnet.public.availability_zone
  size              = 20
  type              = "gp3"
  encrypted         = true

  tags = { Name = "wkx-host-data" }

  lifecycle {
    prevent_destroy = true
  }
}

# The Host: replaceable cattle (ADR 0017). A change to host/cloud-init.yaml
# replaces the instance; the EIP and Data volume carry over.
resource "aws_instance" "host" {
  ami           = nonsensitive(data.aws_ssm_parameter.ubuntu_arm64.value)
  instance_type = "t4g.medium"

  subnet_id = aws_subnet.public.id
  # The IPv6 analogue of the EIP: a fixed address from the subnet's /64, so
  # replacement instances keep it and M3's AAAA record stays valid (ADR 0017).
  ipv6_addresses         = [cidrhost(aws_subnet.public.ipv6_cidr_block, 16)]
  vpc_security_group_ids = [aws_security_group.web.id, aws_security_group.host_egress.id]
  iam_instance_profile   = aws_iam_instance_profile.host.name

  user_data = templatefile("${path.module}/../../host/cloud-init.yaml", {
    data_volume_device = local.data_volume_device
    agent_config_param = aws_ssm_parameter.cloudwatch_agent_config.name
  })
  user_data_replace_on_change = true

  # standard, not the t4g default unlimited: an exhausted credit bank
  # throttles to baseline instead of buying surplus credits.
  credit_specification {
    cpu_credits = "standard"
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
    # Containers must not reach the instance role's credentials: the role
    # reads every /wkx/* Parameter. Hop limit 1 stops IMDSv2 token
    # responses at the bridge-network boundary (ADR 0023, reverses M2).
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size = 12
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = "wkx-host" }

  lifecycle {
    # "current" in the SSM parameter moves with Canonical's releases; a new
    # AMI must never replace the Host by itself. Replacements (bootstrap
    # changes, taint) pick up the then-current AMI.
    ignore_changes = [ami]
  }
}

resource "aws_volume_attachment" "data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.host.id

  # Replacement path: stop the instance, let the filesystem unmount
  # cleanly, then detach. Never force-detach a live volume (ADR 0017).
  stop_instance_before_detaching = true
}

# Encodes the Host invariants as plan-time checks:
# IMDSv2, standard CPU credits, encrypted gp3 volumes, and the
# replaceable-Host / durable-Data-volume stance (ADR 0017).
# Keyless (ADR 0003) cannot be asserted at plan time: key_name is
# Optional+Computed, so a create plan reports it unknown. The live
# posture check after apply verifies KeyName is null instead.
run "host_is_imdsv2_and_cattle" {
  command = plan

  assert {
    condition     = aws_instance.host.metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 must be required on the Host."
  }

  assert {
    condition     = aws_instance.host.ami == nonsensitive(data.aws_ssm_parameter.ubuntu_arm64.value)
    error_message = "The AMI must come from the Canonical SSM parameter, never a hardcoded ID."
  }

  assert {
    condition     = aws_instance.host.credit_specification[0].cpu_credits == "standard"
    error_message = "CPU credits must be standard; unlimited can exceed the budget."
  }

  assert {
    condition     = aws_instance.host.user_data_replace_on_change == true
    error_message = "Bootstrap changes must replace the Host (ADR 0017)."
  }

  assert {
    condition = alltrue([
      aws_instance.host.root_block_device[0].encrypted,
      aws_instance.host.root_block_device[0].volume_type == "gp3",
    ])
    error_message = "The root volume must be encrypted gp3."
  }

  assert {
    condition = alltrue([
      aws_ebs_volume.data.encrypted,
      aws_ebs_volume.data.type == "gp3",
      aws_ebs_volume.data.size == 20,
    ])
    error_message = "The Data volume must be encrypted gp3, 20 GB."
  }

  assert {
    condition     = aws_volume_attachment.data.stop_instance_before_detaching == true
    error_message = "Detaching must stop the instance first for a clean unmount (ADR 0017)."
  }
}

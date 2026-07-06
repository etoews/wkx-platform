# The agent's config travels through SSM Parameter Store: the repo file is
# the source of truth, Terraform publishes it, the Host fetches it at boot
# (cloud-init) or on demand via SSM RunCommand. Config changes therefore
# never replace the Host; ADR 0017 applies only to cloud-init edits.
resource "aws_ssm_parameter" "cloudwatch_agent_config" {
  name  = "/wkx/platform/prod/CLOUDWATCH_AGENT_CONFIG"
  type  = "String"
  value = file("${path.module}/../../host/cloudwatch-agent.json")

  tags = {
    Name = "/wkx/platform/prod/CLOUDWATCH_AGENT_CONFIG"
    Env  = "prod"
  }
}

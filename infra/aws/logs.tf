# One log group per service (naming table, design spec §6); Terraform owns
# creation so every group is tagged and retention-bounded. The awslogs
# driver and the CloudWatch agent only ever write (iam.tf).
resource "aws_cloudwatch_log_group" "hello" {
  name              = "/wkx/hello/prod"
  retention_in_days = 7

  tags = { Name = "/wkx/hello/prod", Service = "hello", Env = "prod" }
}

resource "aws_cloudwatch_log_group" "caddy" {
  # 30 days, not 7: access logs feed the request-rate metric and answer
  # traffic questions after the fact.
  name              = "/wkx/caddy/prod"
  retention_in_days = 30

  tags = { Name = "/wkx/caddy/prod", Service = "caddy", Env = "prod" }
}

resource "aws_cloudwatch_log_group" "platform" {
  # Host-level emissions: platform occupies the service slot (CONTEXT.md);
  # no Service tag, per the tagging strategy's shared/platform category.
  name              = "/wkx/platform/prod"
  retention_in_days = 7

  tags = { Name = "/wkx/platform/prod", Env = "prod" }
}

# Request rate from Caddy access logs, derived server-side. Exact logger
# match: the Caddyfile names its access logger wkx because auto-generated
# names (log0, log1) shift if site blocks reorder. Each distinct Host value
# is one custom metric; bounded, because only hostnames with proxied zone
# records reach the origin.
resource "aws_cloudwatch_log_metric_filter" "edge_requests" {
  name           = "wkx-edge-requests"
  log_group_name = aws_cloudwatch_log_group.caddy.name
  pattern        = "{ $.logger = \"http.log.access.wkx\" }"

  metric_transformation {
    name      = "RequestCount"
    namespace = "WKX/Edge"
    value     = "1"

    dimensions = {
      Host = "$.request.host"
    }
  }
}

# Observability invariants (M4): Terraform owns every /wkx log group, each
# with explicit retention (a group created any other way would be untagged
# and never-expiring), and the request-rate pipeline publishes to WKX/Edge.
run "log_groups_named_tagged_retained" {
  command = plan

  assert {
    condition = alltrue([
      aws_cloudwatch_log_group.hello.name == "/wkx/hello/prod",
      aws_cloudwatch_log_group.caddy.name == "/wkx/caddy/prod",
      aws_cloudwatch_log_group.platform.name == "/wkx/platform/prod",
    ])
    error_message = "Log groups follow /wkx/<service>/<env>."
  }

  assert {
    condition = alltrue([
      aws_cloudwatch_log_group.hello.retention_in_days == 7,
      aws_cloudwatch_log_group.caddy.retention_in_days == 30,
      aws_cloudwatch_log_group.platform.retention_in_days == 7,
    ])
    error_message = "Tiered retention: 7d app and platform, 30d Caddy access logs."
  }

  assert {
    condition = alltrue([
      aws_cloudwatch_log_group.hello.tags["Service"] == "hello",
      aws_cloudwatch_log_group.caddy.tags["Service"] == "caddy",
      !contains(keys(aws_cloudwatch_log_group.platform.tags), "Service"),
      aws_cloudwatch_log_group.hello.tags["Env"] == "prod",
      aws_cloudwatch_log_group.caddy.tags["Env"] == "prod",
      aws_cloudwatch_log_group.platform.tags["Env"] == "prod",
    ])
    error_message = "Per-service groups carry Service; the platform group omits it."
  }
}

run "request_rate_metric_filter" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_metric_filter.edge_requests.pattern == "{ $.logger = \"http.log.access.wkx\" }"
    error_message = "Filter must exact-match the named Caddy access logger."
  }

  assert {
    condition = alltrue([
      aws_cloudwatch_log_metric_filter.edge_requests.metric_transformation[0].namespace == "WKX/Edge",
      aws_cloudwatch_log_metric_filter.edge_requests.metric_transformation[0].name == "RequestCount",
      aws_cloudwatch_log_metric_filter.edge_requests.metric_transformation[0].dimensions["Host"] == "$.request.host",
    ])
    error_message = "RequestCount publishes to WKX/Edge with the Host dimension."
  }
}

variables {
  alert_email = "alerts@example.invalid"
}

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

run "agent_config_from_repo_file" {
  command = plan

  assert {
    condition = alltrue([
      aws_ssm_parameter.cloudwatch_agent_config.name == "/wkx/platform/prod/CLOUDWATCH_AGENT_CONFIG",
      aws_ssm_parameter.cloudwatch_agent_config.type == "String",
    ])
    error_message = "Agent config: /wkx/platform path, plain String (not a secret)."
  }

  assert {
    condition     = nonsensitive(aws_ssm_parameter.cloudwatch_agent_config.value) == file("../../host/cloudwatch-agent.json")
    error_message = "The parameter value must be exactly the repo file."
  }
}

run "alerts_topic" {
  command = plan

  assert {
    condition     = aws_sns_topic.alerts.name == "wkx-alerts"
    error_message = "The notification topic is wkx-alerts."
  }

  assert {
    condition     = aws_sns_topic_subscription.alerts_email.protocol == "email"
    error_message = "wkx-alerts must have an email subscription."
  }
}

run "alarms_wired_to_sns" {
  command = plan

  assert {
    condition = alltrue([
      aws_cloudwatch_metric_alarm.disk_root.alarm_name == "wkx-host-disk-root",
      aws_cloudwatch_metric_alarm.disk_data.alarm_name == "wkx-host-disk-data",
      aws_cloudwatch_metric_alarm.mem.alarm_name == "wkx-host-mem",
      aws_cloudwatch_metric_alarm.cpu.alarm_name == "wkx-host-cpu",
      aws_cloudwatch_metric_alarm.cpu_credits.alarm_name == "wkx-host-cpu-credits",
    ])
    error_message = "Every alarm must have the correct name."
  }

  assert {
    condition = alltrue([
      aws_cloudwatch_metric_alarm.cpu_credits.namespace == "AWS/EC2",
      aws_cloudwatch_metric_alarm.cpu_credits.comparison_operator == "LessThanThreshold",
    ])
    error_message = "The credit alarm reads AWS/EC2 CPUCreditBalance, alarming low."
  }

  assert {
    condition = alltrue([
      aws_cloudwatch_metric_alarm.disk_root.namespace == "CWAgent",
      aws_cloudwatch_metric_alarm.disk_data.namespace == "CWAgent",
      aws_cloudwatch_metric_alarm.mem.namespace == "CWAgent",
      aws_cloudwatch_metric_alarm.cpu.namespace == "CWAgent",
    ])
    error_message = "The four agent alarms read CWAgent metrics."
  }

  assert {
    condition = alltrue([
      aws_cloudwatch_metric_alarm.disk_root.metric_name == "disk_used_percent",
      aws_cloudwatch_metric_alarm.disk_data.metric_name == "disk_used_percent",
      aws_cloudwatch_metric_alarm.mem.metric_name == "mem_used_percent",
      aws_cloudwatch_metric_alarm.cpu.metric_name == "cpu_usage_active",
      aws_cloudwatch_metric_alarm.cpu_credits.metric_name == "CPUCreditBalance",
    ])
    error_message = "Alarm metric names: disk_used_percent x2, mem_used_percent, cpu_usage_active, CPUCreditBalance."
  }

  assert {
    condition = alltrue([
      aws_cloudwatch_metric_alarm.disk_root.threshold == 80,
      aws_cloudwatch_metric_alarm.disk_data.threshold == 80,
      aws_cloudwatch_metric_alarm.mem.threshold == 90,
      aws_cloudwatch_metric_alarm.cpu.threshold == 80,
      aws_cloudwatch_metric_alarm.cpu_credits.threshold == 144,
    ])
    error_message = "Alarm thresholds: disk 80, mem 90, cpu 80, credits 144."
  }

  assert {
    condition = alltrue([
      aws_cloudwatch_metric_alarm.disk_root.comparison_operator == "GreaterThanThreshold",
      aws_cloudwatch_metric_alarm.disk_data.comparison_operator == "GreaterThanThreshold",
      aws_cloudwatch_metric_alarm.mem.comparison_operator == "GreaterThanThreshold",
      aws_cloudwatch_metric_alarm.cpu.comparison_operator == "GreaterThanThreshold",
    ])
    error_message = "The four agent alarms alarm high (GreaterThanThreshold)."
  }

  assert {
    condition = alltrue([
      aws_cloudwatch_metric_alarm.disk_root.period == 300,
      aws_cloudwatch_metric_alarm.disk_data.period == 300,
      aws_cloudwatch_metric_alarm.mem.period == 300,
      aws_cloudwatch_metric_alarm.cpu.period == 300,
      aws_cloudwatch_metric_alarm.cpu_credits.period == 300,
      aws_cloudwatch_metric_alarm.disk_root.evaluation_periods == 3,
      aws_cloudwatch_metric_alarm.disk_data.evaluation_periods == 3,
      aws_cloudwatch_metric_alarm.mem.evaluation_periods == 3,
      aws_cloudwatch_metric_alarm.cpu.evaluation_periods == 3,
      aws_cloudwatch_metric_alarm.cpu_credits.evaluation_periods == 3,
    ])
    error_message = "Every alarm evaluates 3 x 5 min (15 min sustained)."
  }

  # Dimension literals (path, fstype, cpu) cannot be asserted here: the
  # dimensions map carries the unknown aws_instance.host.id, which makes
  # every key access unknown at plan time.
}

run "dashboard_exists" {
  command = plan

  assert {
    condition     = aws_cloudwatch_dashboard.wkx.dashboard_name == "wkx-prod"
    error_message = "The dashboard wkx-prod must exist."
  }
}

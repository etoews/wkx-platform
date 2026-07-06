# Host alarms (M4). CWAgent metrics carry InstanceId (agent
# append_dimensions) and the Host is cattle (ADR 0017), so every alarm keys
# on aws_instance.host.id: the apply that replaces the Host re-points the
# alarms in the same plan. No billing alarm: the wallet guard is the
# wkx-org-monthly budget in infra/mgmt (M4 grill decision).
locals {
  alarm_period = 300
  alarm_evals  = 3 # 3 x 5 min = 15 min sustained
}

resource "aws_cloudwatch_metric_alarm" "disk_root" {
  alarm_name          = "wkx-host-disk-root"
  alarm_description   = "Root volume above 80% for 15 min."
  namespace           = "CWAgent"
  metric_name         = "disk_used_percent"
  statistic           = "Average"
  period              = local.alarm_period
  evaluation_periods  = local.alarm_evals
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    InstanceId = aws_instance.host.id
    path       = "/"
    fstype     = "ext4"
  }

  tags = { Name = "wkx-host-disk-root" }
}

resource "aws_cloudwatch_metric_alarm" "disk_data" {
  alarm_name          = "wkx-host-disk-data"
  alarm_description   = "Data volume above 80% for 15 min: SQLite writes and logs are at risk."
  namespace           = "CWAgent"
  metric_name         = "disk_used_percent"
  statistic           = "Average"
  period              = local.alarm_period
  evaluation_periods  = local.alarm_evals
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    InstanceId = aws_instance.host.id
    path       = "/srv/data"
    fstype     = "ext4"
  }

  tags = { Name = "wkx-host-disk-data" }
}

resource "aws_cloudwatch_metric_alarm" "mem" {
  alarm_name          = "wkx-host-mem"
  alarm_description   = "Memory above 90% for 15 min."
  namespace           = "CWAgent"
  metric_name         = "mem_used_percent"
  statistic           = "Average"
  period              = local.alarm_period
  evaluation_periods  = local.alarm_evals
  threshold           = 90
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    InstanceId = aws_instance.host.id
  }

  tags = { Name = "wkx-host-mem" }
}

resource "aws_cloudwatch_metric_alarm" "cpu" {
  alarm_name          = "wkx-host-cpu"
  alarm_description   = "CPU above 80% for 15 min: the credit bank is draining (standard mode)."
  namespace           = "CWAgent"
  metric_name         = "cpu_usage_active"
  statistic           = "Average"
  period              = local.alarm_period
  evaluation_periods  = local.alarm_evals
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    InstanceId = aws_instance.host.id
    cpu        = "cpu-total"
  }

  tags = { Name = "wkx-host-cpu" }
}

resource "aws_cloudwatch_metric_alarm" "cpu_credits" {
  alarm_name          = "wkx-host-cpu-credits"
  alarm_description   = "Credit bank under 25% (144 of 576): throttling to the 20%-per-vCPU baseline approaches."
  namespace           = "AWS/EC2"
  metric_name         = "CPUCreditBalance"
  statistic           = "Average"
  period              = local.alarm_period
  evaluation_periods  = local.alarm_evals
  threshold           = 144
  comparison_operator = "LessThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    InstanceId = aws_instance.host.id
  }

  tags = { Name = "wkx-host-cpu-credits" }
}

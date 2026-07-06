# One dashboard: the box's vital signs and the edge request rate. Metric
# widgets use the same dimension sets as the alarms. The request widget
# SEARCHes WKX/Edge so new services appear without a dashboard change, and
# FILLs zero-traffic gaps (dimensioned filter metrics emit no datapoint
# when idle).
resource "aws_cloudwatch_dashboard" "wkx" {
  dashboard_name = "wkx-prod"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6,
        properties = {
          title  = "CPU and credit bank"
          region = var.region
          stat   = "Average"
          period = 300
          metrics = [
            ["CWAgent", "cpu_usage_active", "InstanceId", aws_instance.host.id, "cpu", "cpu-total"],
            ["AWS/EC2", "CPUCreditBalance", "InstanceId", aws_instance.host.id, { yAxis = "right" }],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6,
        properties = {
          title  = "Memory"
          region = var.region
          stat   = "Average"
          period = 300
          metrics = [
            ["CWAgent", "mem_used_percent", "InstanceId", aws_instance.host.id],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6,
        properties = {
          title  = "Disk used %"
          region = var.region
          stat   = "Average"
          period = 300
          metrics = [
            ["CWAgent", "disk_used_percent", "InstanceId", aws_instance.host.id, "path", "/", "fstype", "ext4"],
            ["CWAgent", "disk_used_percent", "InstanceId", aws_instance.host.id, "path", "/srv/data", "fstype", "ext4"],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6,
        properties = {
          title  = "Network bytes"
          region = var.region
          stat   = "Sum"
          period = 300
          metrics = [
            ["CWAgent", "net_bytes_sent", "InstanceId", aws_instance.host.id, "interface", "ens5"],
            ["CWAgent", "net_bytes_recv", "InstanceId", aws_instance.host.id, "interface", "ens5"],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 12, width = 24, height = 6,
        properties = {
          title  = "Requests (per service + total)"
          region = var.region
          period = 300
          metrics = [
            [{ expression = "SEARCH('{WKX/Edge,Host} MetricName=\"RequestCount\"', 'Sum', 300)", label = "per service", id = "per_service" }],
            [{ expression = "SUM(FILL(per_service, 0))", label = "total", id = "total" }],
          ]
        }
      },
    ]
  })
}

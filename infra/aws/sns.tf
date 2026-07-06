# One notification channel for every host alarm. Email is the only
# subscriber; the address never appears in committed files (invariant 7).
resource "aws_sns_topic" "alerts" {
  name = "wkx-alerts"

  tags = { Name = "wkx-alerts" }
}

resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

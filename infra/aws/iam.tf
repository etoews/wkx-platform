data "aws_caller_identity" "current" {}

resource "aws_iam_role" "host" {
  name = "wkx-host"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "wkx-host" }
}

# SSM Session Manager + RunCommand agent permissions.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.host.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Pull-only ECR access. GetAuthorizationToken cannot be resource-scoped.
resource "aws_iam_role_policy" "ecr_pull" {
  name = "ecr-pull"
  role = aws_iam_role.host.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrAuthToken"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "EcrPullOnly"
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability",
        ]
        Resource = "arn:aws:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/*"
      },
    ]
  })
}

# Log groups are created by Terraform (logs.tf); the box only writes.
# PutMetricData stays pinned to the agent's default CWAgent namespace,
# which M4 kept.
resource "aws_iam_role_policy" "cloudwatch_write" {
  name = "cloudwatch-write"
  role = aws_iam_role.host.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WkxLogGroupsWrite"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
        ]
        Resource = [
          "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/wkx/*",
          "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/wkx/*:*",
        ]
      },
      {
        Sid       = "CwAgentMetrics"
        Effect    = "Allow"
        Action    = "cloudwatch:PutMetricData"
        Resource  = "*"
        Condition = { StringEquals = { "cloudwatch:namespace" = "CWAgent" } }
      },
    ]
  })
}

resource "aws_iam_role_policy" "ssm_params_read" {
  name = "ssm-params-read"
  role = aws_iam_role.host.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "WkxParamsRead"
      Effect = "Allow"
      Action = [
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:GetParametersByPath",
      ]
      Resource = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/wkx/*"
    }]
  })
}

resource "aws_iam_instance_profile" "host" {
  name = "wkx-host"
  role = aws_iam_role.host.name

  tags = { Name = "wkx-host" }
}

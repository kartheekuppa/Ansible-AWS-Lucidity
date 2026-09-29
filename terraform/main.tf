terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# ============================================================================
# Management Account Role (AssumeRole caller)
# ============================================================================

resource "aws_iam_role" "ansible_manager" {
  name               = "AnsibleManager"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
          AWS     = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "AnsibleManager"
    Environment = "management"
    Purpose     = "Cross-account Ansible orchestration"
  }
}

resource "aws_iam_role_policy" "ansible_manager_policy" {
  name = "AnsibleManagerPolicy"
  role = aws_iam_role.ansible_manager.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAssumeRoleInChildAccounts"
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = "arn:aws:iam::*:role/AnsibleExecutor"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = var.external_id
          }
        }
      },
      {
        Sid    = "AllowEC2Describe"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ansible_manager" {
  name = "AnsibleManager-Profile"
  role = aws_iam_role.ansible_manager.name
}

# ============================================================================
# Child Account Role (Executor in monitored accounts)
# ============================================================================

resource "aws_iam_role" "ansible_executor" {
  count = length(var.child_accounts) > 0 ? 1 : 0

  name               = "AnsibleExecutor"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/AnsibleManager"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = var.external_id
          }
        }
      }
    ]
  })

  tags = {
    Name        = "AnsibleExecutor"
    Environment = "child"
    Purpose     = "Executed by AnsibleManager for disk monitoring"
  }
}

resource "aws_iam_role_policy" "ansible_executor_policy" {
  count = length(var.child_accounts) > 0 ? 1 : 0

  name = "AnsibleExecutorPolicy"
  role = aws_iam_role.ansible_executor[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSSMSendCommand"
        Effect = "Allow"
        Action = [
          "ssm:SendCommand",
          "ssm:GetCommandInvocation"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowEC2Describe"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowCloudWatchMetrics"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:log-group:/ansible/*"
      },
      {
        Sid    = "AllowSNSPublish"
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = "arn:aws:sns:*:*:*"
      }
    ]
  })
}

# ============================================================================
# CloudWatch Log Group for Ansible
# ============================================================================

resource "aws_cloudwatch_log_group" "ansible" {
  name              = "/ansible/disk-metrics"
  retention_in_days = 30

  tags = {
    Name        = "AnsibleDiskMetrics"
    Environment = "shared"
  }
}

# ============================================================================
# SNS Topic for Disk Alerts
# ============================================================================

resource "aws_sns_topic" "disk_alerts" {
  name = "DiskUsageAlerts"

  tags = {
    Name        = "DiskUsageAlerts"
    Environment = "shared"
  }
}

resource "aws_sns_topic_subscription" "disk_alerts_email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.disk_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ============================================================================
# Data Sources
# ============================================================================

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

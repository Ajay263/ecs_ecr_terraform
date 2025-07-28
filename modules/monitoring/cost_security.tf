# modules/monitoring/cost_security.tf - Fixed Cost and Security Monitoring

# ============================================================================
# COST MONITORING - SIMPLIFIED FOR COMPATIBILITY
# ============================================================================

# Budget for ECS Services (Fixed configuration)
resource "aws_budgets_budget" "ecs_monthly_budget" {
  name         = "${var.cluster_name}-monthly-budget"
  budget_type  = "COST"
  limit_amount = "100"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  time_period_start = formatdate("YYYY-MM-01_00:00", timestamp())

  cost_filter {
    name = "Service"
    values = [
      "Amazon Elastic Container Service",
      "Amazon Elastic Load Balancing",
      "Amazon EC2-Instance"
    ]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = var.notification_emails
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.notification_emails
  }

  tags = var.tags
}

# Cost alert using CloudWatch metric (Alternative approach)
resource "aws_cloudwatch_metric_alarm" "high_estimated_charges" {
  count = length(var.notification_emails) > 0 ? 1 : 0

  alarm_name          = "${var.cluster_name}-high-estimated-charges"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = "86400"  # 24 hours
  statistic           = "Maximum"
  threshold           = "50"     # $50 daily threshold
  alarm_description   = "High estimated charges for ${var.cluster_name} resources"
  alarm_actions       = [aws_sns_topic.monitoring.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    Currency = "USD"
  }

  tags = var.tags
}

# ============================================================================
# CLOUDTRAIL FOR SECURITY MONITORING
# ============================================================================

# S3 bucket for CloudTrail logs
resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket        = "${var.cluster_name}-cloudtrail-logs-${random_id.bucket_suffix.hex}"
  force_destroy = true
  tags          = var.tags
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket policy for CloudTrail
resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  depends_on = [aws_s3_bucket_public_access_block.cloudtrail_logs]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail_logs.arn
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${var.cluster_name}-security-trail"
          }
        }
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail_logs.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
            "AWS:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${var.cluster_name}-security-trail"
          }
        }
      }
    ]
  })
}

# CloudTrail for API monitoring
resource "aws_cloudtrail" "security_trail" {
  depends_on = [aws_s3_bucket_policy.cloudtrail_logs]

  name           = "${var.cluster_name}-security-trail"
  s3_bucket_name = aws_s3_bucket.cloudtrail_logs.bucket

  # Simplified event selector - management events only
  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  tags = var.tags
}

# CloudWatch log group for CloudTrail
resource "aws_cloudwatch_log_group" "cloudtrail_logs" {
  name              = "/aws/cloudtrail/${var.cluster_name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# ============================================================================
# SECURITY MONITORING METRIC FILTERS
# ============================================================================

# Root account usage metric filter
resource "aws_cloudwatch_log_metric_filter" "root_account_usage" {
  name           = "${var.cluster_name}-root-account-usage"
  log_group_name = aws_cloudwatch_log_group.cloudtrail_logs.name
  pattern        = "{ $.userIdentity.type = \"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != \"AwsServiceEvent\" }"

  metric_transformation {
    name      = "RootAccountUsage"
    namespace = "${var.cluster_name}/Security"
    value     = "1"
    unit      = "Count"
  }
}

# Failed login attempts metric filter
resource "aws_cloudwatch_log_metric_filter" "failed_logins" {
  name           = "${var.cluster_name}-failed-logins"
  log_group_name = aws_cloudwatch_log_group.cloudtrail_logs.name
  pattern        = "{ ($.errorCode = \"*UnauthorizedOperation\") || ($.errorCode = \"AccessDenied*\") }"

  metric_transformation {
    name      = "FailedLoginAttempts"
    namespace = "${var.cluster_name}/Security"
    value     = "1"
    unit      = "Count"
  }
}

# Unauthorized API calls metric filter
resource "aws_cloudwatch_log_metric_filter" "unauthorized_api_calls" {
  name           = "${var.cluster_name}-unauthorized-api-calls"
  log_group_name = aws_cloudwatch_log_group.cloudtrail_logs.name
  pattern        = "{ ($.errorCode = \"*UnauthorizedOperation\") || ($.errorCode = \"AccessDenied*\") || ($.errorCode = \"InvalidUserID.NotFound\") }"

  metric_transformation {
    name      = "UnauthorizedAPICalls"
    namespace = "${var.cluster_name}/Security"
    value     = "1"
    unit      = "Count"
  }
}

# ============================================================================
# SECURITY MONITORING ALARMS
# ============================================================================

# Root account usage alarm
resource "aws_cloudwatch_metric_alarm" "root_account_usage" {
  alarm_name          = "${var.cluster_name}-root-account-usage"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "RootAccountUsage"
  namespace           = "${var.cluster_name}/Security"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "Root account usage detected - security concern"
  alarm_actions       = [aws_sns_topic.monitoring.arn]
  treat_missing_data  = "notBreaching"

  tags = var.tags
}

# Multiple failed logins alarm
resource "aws_cloudwatch_metric_alarm" "failed_logins" {
  alarm_name          = "${var.cluster_name}-multiple-failed-logins"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FailedLoginAttempts"
  namespace           = "${var.cluster_name}/Security"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "Multiple failed login attempts detected"
  alarm_actions       = [aws_sns_topic.monitoring.arn]
  treat_missing_data  = "notBreaching"

  tags = var.tags
}

# Unauthorized API calls alarm
resource "aws_cloudwatch_metric_alarm" "unauthorized_api_calls" {
  alarm_name          = "${var.cluster_name}-unauthorized-api-calls"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "UnauthorizedAPICalls"
  namespace           = "${var.cluster_name}/Security"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "High number of unauthorized API calls"
  alarm_actions       = [aws_sns_topic.monitoring.arn]
  treat_missing_data  = "notBreaching"

  tags = var.tags
}

# ============================================================================
# NETWORK MONITORING (VPC Flow Logs)
# ============================================================================

# IAM role for VPC Flow Logs
resource "aws_iam_role" "flow_logs_role" {
  name = "${var.cluster_name}-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# IAM policy for VPC Flow Logs
resource "aws_iam_role_policy" "flow_logs_policy" {
  name = "${var.cluster_name}-flow-logs-policy"
  role = aws_iam_role.flow_logs_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# CloudWatch log group for VPC Flow Logs
resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/flowlogs/${var.cluster_name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# ============================================================================
# CONTAINER INSIGHTS CONFIGURATION
# ============================================================================

# CloudWatch log group for Container Insights
resource "aws_cloudwatch_log_group" "container_insights" {
  count = var.enable_container_insights ? 1 : 0

  name              = "/aws/ecs/containerinsights/${var.cluster_name}/performance"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# ============================================================================
# OUTPUTS FOR SECURITY RESOURCES
# ============================================================================

output "cloudtrail_bucket_name" {
  description = "Name of the S3 bucket for CloudTrail logs"
  value       = aws_s3_bucket.cloudtrail_logs.bucket
}

output "security_alarm_names" {
  description = "List of security-related alarm names"
  value = [
    aws_cloudwatch_metric_alarm.root_account_usage.alarm_name,
    aws_cloudwatch_metric_alarm.failed_logins.alarm_name,
    aws_cloudwatch_metric_alarm.unauthorized_api_calls.alarm_name
  ]
}
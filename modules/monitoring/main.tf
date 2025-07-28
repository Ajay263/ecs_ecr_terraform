# modules/monitoring/main.tf - Enhanced Monitoring Stack

# Data sources for existing resources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
}

# ============================================================================
# LOG GROUPS AND EVENT BRIDGE SETUP
# ============================================================================

# CloudWatch log group for ECS events
resource "aws_cloudwatch_log_group" "ecs_events" {
  name              = "/aws/events/ecs"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# CloudWatch log group for application logs
resource "aws_cloudwatch_log_group" "app_logs" {
  for_each = var.applications

  name              = "/ecs/${var.cluster_name}/${each.key}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# CloudWatch log group for ALB logs
resource "aws_cloudwatch_log_group" "alb_logs" {
  name              = "/aws/applicationelb/${var.cluster_name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# EventBridge rule for ECS events
resource "aws_cloudwatch_event_rule" "ecs_events" {
  name        = "${var.cluster_name}-ecs-events"
  description = "Capture all ECS events for cluster ${var.cluster_name}"

  event_pattern = jsonencode({
    source = ["aws.ecs"]
    detail = {
      clusterArn = [var.cluster_arn]
    }
  })
  tags = var.tags
}

# EventBridge target to send events to CloudWatch logs
resource "aws_cloudwatch_event_target" "logs" {
  rule      = aws_cloudwatch_event_rule.ecs_events.name
  target_id = "send-to-cloudwatch"
  arn       = aws_cloudwatch_log_group.ecs_events.arn
}

# Resource policy to allow EventBridge to write to CloudWatch Logs
resource "aws_cloudwatch_log_resource_policy" "eventbridge_logs_policy" {
  policy_name = "${var.cluster_name}-eventbridge-logs-policy"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EventBridgeLogsPolicy"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.ecs_events.arn}:*"
      }
    ]
  })
}

# ============================================================================
# METRIC FILTERS
# ============================================================================

# ECS Task State Changes
resource "aws_cloudwatch_log_metric_filter" "ecs_task_failures" {
  name           = "${var.cluster_name}-ecs-task-failures"
  log_group_name = aws_cloudwatch_log_group.ecs_events.name
  pattern        = "\"ECS Task State Change\""

  metric_transformation {
    name      = "ECSTaskStateChanges"
    namespace = "${var.cluster_name}/ECS/Events"
    value     = "1"
    unit      = "Count"
  }
}

# ECS Service Events
resource "aws_cloudwatch_log_metric_filter" "ecs_service_events" {
  name           = "${var.cluster_name}-ecs-service-events"
  log_group_name = aws_cloudwatch_log_group.ecs_events.name
  pattern        = "\"ECS Service Action\""

  metric_transformation {
    name      = "ECSServiceEvents"
    namespace = "${var.cluster_name}/ECS/Events"
    value     = "1"
    unit      = "Count"
  }
}

# Application Error Metrics
resource "aws_cloudwatch_log_metric_filter" "app_errors" {
  for_each = var.applications

  name           = "${var.cluster_name}-${each.key}-errors"
  log_group_name = aws_cloudwatch_log_group.app_logs[each.key].name
  pattern        = "ERROR"

  metric_transformation {
    name      = "ApplicationErrors"
    namespace = "${var.cluster_name}/Applications/${each.key}"
    value     = "1"
    unit      = "Count"
  }
}

# Flask 5xx Errors (for API service)
resource "aws_cloudwatch_log_metric_filter" "flask_5xx_errors" {
  count = contains(keys(var.applications), "api") ? 1 : 0

  name           = "${var.cluster_name}-api-5xx-errors"
  log_group_name = aws_cloudwatch_log_group.app_logs["api"].name
  pattern        = "[timestamp, level=\"ERROR\", ..., status_code=5*]"

  metric_transformation {
    name      = "Flask5xxErrors"
    namespace = "${var.cluster_name}/Applications/api"
    value     = "1"
    unit      = "Count"
  }
}

# Application Warnings
resource "aws_cloudwatch_log_metric_filter" "app_warnings" {
  for_each = var.applications

  name           = "${var.cluster_name}-${each.key}-warnings"
  log_group_name = aws_cloudwatch_log_group.app_logs[each.key].name
  pattern        = "WARN"

  metric_transformation {
    name      = "ApplicationWarnings"
    namespace = "${var.cluster_name}/Applications/${each.key}"
    value     = "1"
    unit      = "Count"
  }
}

# ============================================================================
# SNS TOPIC AND IAM ROLES
# ============================================================================

# SNS topic for monitoring alerts
resource "aws_sns_topic" "monitoring" {
  name = "${var.cluster_name}-monitoring"

  lambda_success_feedback_role_arn    = aws_iam_role.sns_delivery_status.arn
  lambda_failure_feedback_role_arn    = aws_iam_role.sns_delivery_status.arn
  lambda_success_feedback_sample_rate = 100

  tags = var.tags
}

# SNS topic policy
resource "aws_sns_topic_policy" "monitoring" {
  arn = aws_sns_topic.monitoring.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "${var.cluster_name}-monitoring-policy"
    Statement = [
      {
        Sid    = "AllowCloudWatchAlarmsToPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.monitoring.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })
}

# SNS subscriptions
resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.notification_emails)

  topic_arn = aws_sns_topic.monitoring.arn
  protocol  = "email"
  endpoint  = each.value
}

# IAM role for SNS delivery status logging
resource "aws_iam_role" "sns_delivery_status" {
  name = "${var.cluster_name}-sns-delivery-status"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  tags = var.tags
}

resource "aws_iam_policy" "sns_delivery_status" {
  name = "${var.cluster_name}-sns-delivery-status"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:PutMetricFilter",
          "logs:PutRetentionPolicy"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "sns_delivery_status" {
  role       = aws_iam_role.sns_delivery_status.name
  policy_arn = aws_iam_policy.sns_delivery_status.arn
}

# ============================================================================
# ECS PERFORMANCE ALARMS
# ============================================================================

# High CPU Utilization per Service
resource "aws_cloudwatch_metric_alarm" "ecs_high_cpu" {
  for_each = var.applications

  alarm_name          = "${var.cluster_name}-${each.key}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.cpu_threshold
  alarm_description   = "High CPU utilization for ${each.key} service (>${var.cpu_threshold}%)"
  alarm_actions       = [aws_sns_topic.monitoring.arn]
  ok_actions          = [aws_sns_topic.monitoring.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    ServiceName = "${each.key}-service"
    ClusterName = var.cluster_name
  }
  tags = var.tags
}

# High Memory Utilization per Service
resource "aws_cloudwatch_metric_alarm" "ecs_high_memory" {
  for_each = var.applications

  alarm_name          = "${var.cluster_name}-${each.key}-high-memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.memory_threshold
  alarm_description   = "High memory utilization for ${each.key} service (>${var.memory_threshold}%)"
  alarm_actions       = [aws_sns_topic.monitoring.arn]
  ok_actions          = [aws_sns_topic.monitoring.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    ServiceName = "${each.key}-service"
    ClusterName = var.cluster_name
  }
  tags = var.tags
}

# Low Running Task Count
resource "aws_cloudwatch_metric_alarm" "ecs_low_task_count" {
  for_each = var.applications

  alarm_name          = "${var.cluster_name}-${each.key}-low-task-count"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "RunningCount"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "Low running task count for ${each.key} service"
  alarm_actions       = [aws_sns_topic.monitoring.arn]
  ok_actions          = [aws_sns_topic.monitoring.arn]
  treat_missing_data  = "breaching"

  dimensions = {
    ServiceName = "${each.key}-service"
    ClusterName = var.cluster_name
  }
  tags = var.tags
}

# ============================================================================
# ALB PERFORMANCE ALARMS
# ============================================================================

# ALB Target Response Time
resource "aws_cloudwatch_metric_alarm" "alb_high_response_time" {
  for_each = var.target_groups

  alarm_name          = "${var.cluster_name}-${each.key}-high-response-time"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Average"
  threshold           = var.alb_response_time_threshold
  alarm_description   = "High response time for ${each.key} (>${var.alb_response_time_threshold}s)"
  alarm_actions       = [aws_sns_topic.monitoring.arn]
  ok_actions          = [aws_sns_topic.monitoring.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    TargetGroup  = each.value
    LoadBalancer = var.load_balancer_arn_suffix
  }
  tags = var.tags
}

# ALB Unhealthy Targets
resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_targets" {
  for_each = var.target_groups

  alarm_name          = "${var.cluster_name}-${each.key}-unhealthy-targets"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Average"
  threshold           = "0"
  alarm_description   = "Unhealthy targets detected for ${each.key}"
  alarm_actions       = [aws_sns_topic.monitoring.arn]
  ok_actions          = [aws_sns_topic.monitoring.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    TargetGroup  = each.value
    LoadBalancer = var.load_balancer_arn_suffix
  }
  tags = var.tags
}

# ALB 5xx Error Rate
resource "aws_cloudwatch_metric_alarm" "alb_5xx_errors" {
  alarm_name          = "${var.cluster_name}-alb-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.alb_5xx_threshold
  alarm_description   = "High 5xx error rate from ALB (>${var.alb_5xx_threshold} errors)"
  alarm_actions       = [aws_sns_topic.monitoring.arn]
  ok_actions          = [aws_sns_topic.monitoring.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.load_balancer_arn_suffix
  }
  tags = var.tags
}

# ALB 4xx Error Rate (for monitoring client errors)
resource "aws_cloudwatch_metric_alarm" "alb_4xx_errors" {
  alarm_name          = "${var.cluster_name}-alb-4xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HTTPCode_ELB_4XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.alb_4xx_threshold
  alarm_description   = "High 4xx error rate from ALB (>${var.alb_4xx_threshold} errors)"
  alarm_actions       = [aws_sns_topic.monitoring.arn]
  ok_actions          = [aws_sns_topic.monitoring.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.load_balancer_arn_suffix
  }
  tags = var.tags
}

# ALB Request Count (for monitoring traffic patterns)
resource "aws_cloudwatch_metric_alarm" "alb_low_request_count" {
  alarm_name          = "${var.cluster_name}-alb-low-traffic"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "RequestCount"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "Unusually low traffic to ALB (<10 requests in 5 minutes)"
  alarm_actions       = [aws_sns_topic.monitoring.arn]
  ok_actions          = [aws_sns_topic.monitoring.arn]
  treat_missing_data  = "breaching"

  dimensions = {
    LoadBalancer = var.load_balancer_arn_suffix
  }
  tags = var.tags
}

# ============================================================================
# APPLICATION-SPECIFIC ALARMS
# ============================================================================

# Flask API 5xx Error Rate
resource "aws_cloudwatch_metric_alarm" "flask_5xx_errors" {
  count = contains(keys(var.applications), "api") ? 1 : 0

  alarm_name          = "${var.cluster_name}-api-flask-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Flask5xxErrors"
  namespace           = "${var.cluster_name}/Applications/api"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.flask_5xx_threshold
  alarm_description   = "High 5xx error rate from Flask API (>${var.flask_5xx_threshold} errors)"
  alarm_actions       = [aws_sns_topic.monitoring.arn]
  ok_actions          = [aws_sns_topic.monitoring.arn]
  treat_missing_data  = "notBreaching"

  tags = var.tags
}

# Application Error Rate
resource "aws_cloudwatch_metric_alarm" "application_errors" {
  for_each = var.applications

  alarm_name          = "${var.cluster_name}-${each.key}-app-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ApplicationErrors"
  namespace           = "${var.cluster_name}/Applications/${each.key}"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.error_threshold
  alarm_description   = "High error rate for ${each.key} application (>${var.error_threshold} errors)"
  alarm_actions       = [aws_sns_topic.monitoring.arn]
  ok_actions          = [aws_sns_topic.monitoring.arn]
  treat_missing_data  = "notBreaching"

  tags = var.tags
}

# ============================================================================
# COMPOSITE ALARMS (ADVANCED MONITORING)
# ============================================================================

# Service Health Composite Alarm
resource "aws_cloudwatch_composite_alarm" "service_health" {
  for_each = var.applications

  alarm_name        = "${var.cluster_name}-${each.key}-service-health"
  alarm_description = "Composite alarm for overall ${each.key} service health"

  alarm_rule = join(" OR ", compact([
    "ALARM(${aws_cloudwatch_metric_alarm.ecs_high_cpu[each.key].alarm_name})",
    "ALARM(${aws_cloudwatch_metric_alarm.ecs_high_memory[each.key].alarm_name})",
    "ALARM(${aws_cloudwatch_metric_alarm.ecs_low_task_count[each.key].alarm_name})",
    try("ALARM(${aws_cloudwatch_metric_alarm.alb_unhealthy_targets[each.key].alarm_name})", ""),
    try("ALARM(${aws_cloudwatch_metric_alarm.alb_high_response_time[each.key].alarm_name})", "")
  ]))

  alarm_actions = [aws_sns_topic.monitoring.arn]
  ok_actions    = [aws_sns_topic.monitoring.arn]

  tags = var.tags
}

# ============================================================================
# CLOUDWATCH DASHBOARD
# ============================================================================

resource "aws_cloudwatch_dashboard" "comprehensive_monitoring" {
  dashboard_name = "${var.cluster_name}-comprehensive-monitoring"

  dashboard_body = jsonencode({
    widgets = [
      # ECS CPU and Memory Overview
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            for app_name in keys(var.applications) : [
              "AWS/ECS", "CPUUtilization", "ServiceName", "${app_name}-service", "ClusterName", var.cluster_name
            ]
          ]
          view    = "timeSeries"
          stacked = false
          region  = local.region
          title   = "ECS CPU Utilization (%)"
          period  = 300
          yAxis = {
            left = { min = 0, max = 100 }
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            for app_name in keys(var.applications) : [
              "AWS/ECS", "MemoryUtilization", "ServiceName", "${app_name}-service", "ClusterName", var.cluster_name
            ]
          ]
          view    = "timeSeries"
          stacked = false
          region  = local.region
          title   = "ECS Memory Utilization (%)"
          period  = 300
          yAxis = {
            left = { min = 0, max = 100 }
          }
        }
      },
      # ALB Performance Metrics
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.load_balancer_arn_suffix],
            [".", "HTTPCode_ELB_2XX_Count", ".", "."],
            [".", "HTTPCode_ELB_4XX_Count", ".", "."],
            [".", "HTTPCode_ELB_5XX_Count", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = local.region
          title   = "ALB Request Count & HTTP Status Codes"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 6
        width  = 8
        height = 6
        properties = {
          metrics = [
            for tg_name in keys(var.target_groups) : [
              "AWS/ApplicationELB", "TargetResponseTime", "TargetGroup", var.target_groups[tg_name], "LoadBalancer", var.load_balancer_arn_suffix
            ]
          ]
          view    = "timeSeries"
          stacked = false
          region  = local.region
          title   = "ALB Response Time (seconds)"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 6
        width  = 8
        height = 6
        properties = {
          metrics = [
            for tg_name in keys(var.target_groups) : [
              "AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", var.target_groups[tg_name], "LoadBalancer", var.load_balancer_arn_suffix
            ]
          ]
          view    = "timeSeries"
          stacked = false
          region  = local.region
          title   = "ALB Healthy Target Count"
          period  = 300
        }
      },
      # Application Error Metrics
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          metrics = [
            for app_name in keys(var.applications) : [
              "${var.cluster_name}/Applications/${app_name}", "ApplicationErrors"
            ]
          ]
          view    = "timeSeries"
          stacked = false
          region  = local.region
          title   = "Application Errors by Service"
          period  = 300
        }
      },
      # ECS Task Count
      {
        type   = "metric"
        x      = 12
        y      = 12
        width  = 12
        height = 6
        properties = {
          metrics = [
            for app_name in keys(var.applications) : [
              "AWS/ECS", "RunningCount", "ServiceName", "${app_name}-service", "ClusterName", var.cluster_name
            ]
          ]
          view    = "timeSeries"
          stacked = false
          region  = local.region
          title   = "ECS Running Task Count"
          period  = 300
        }
      },
      # Recent Logs Query
      {
        type   = "log"
        x      = 0
        y      = 18
        width  = 24
        height = 6
        properties = {
          query   = "SOURCE '${aws_cloudwatch_log_group.ecs_events.name}' | fields @timestamp, @message | filter @message like /STOPPED/ or @message like /ERROR/ | sort @timestamp desc | limit 50"
          region  = local.region
          title   = "Recent ECS Events & Errors"
          view    = "table"
        }
      }
    ]
  })
}
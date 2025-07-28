# modules/monitoring/outputs.tf

# ============================================================================
# SNS AND NOTIFICATION OUTPUTS
# ============================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for monitoring alerts"
  value       = aws_sns_topic.monitoring.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for monitoring alerts"
  value       = aws_sns_topic.monitoring.name
}

# ============================================================================
# CLOUDWATCH LOG GROUPS
# ============================================================================

output "cloudwatch_log_groups" {
  description = "Map of CloudWatch log group names"
  value = {
    ecs_events = aws_cloudwatch_log_group.ecs_events.name
    alb_logs   = aws_cloudwatch_log_group.alb_logs.name
    app_logs   = { for k, v in aws_cloudwatch_log_group.app_logs : k => v.name }
  }
}

# ============================================================================
# DASHBOARD AND MONITORING URLS
# ============================================================================

output "dashboard_url" {
  description = "URL to the comprehensive CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.comprehensive_monitoring.dashboard_name}"
}

output "cloudwatch_alarms_url" {
  description = "URL to CloudWatch Alarms console"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#alarmsV2:"
}

output "cloudwatch_logs_url" {
  description = "URL to CloudWatch Logs console"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups"
}

# ============================================================================
# ALARM INFORMATION
# ============================================================================

output "alarm_names" {
  description = "List of all alarm names created"
  value = concat(
    # ECS Performance Alarms
    [for alarm in aws_cloudwatch_metric_alarm.ecs_high_cpu : alarm.alarm_name],
    [for alarm in aws_cloudwatch_metric_alarm.ecs_high_memory : alarm.alarm_name],
    [for alarm in aws_cloudwatch_metric_alarm.ecs_low_task_count : alarm.alarm_name],
    
    # ALB Performance Alarms
    [for alarm in aws_cloudwatch_metric_alarm.alb_high_response_time : alarm.alarm_name],
    [for alarm in aws_cloudwatch_metric_alarm.alb_unhealthy_targets : alarm.alarm_name],
    [aws_cloudwatch_metric_alarm.alb_5xx_errors.alarm_name],
    [aws_cloudwatch_metric_alarm.alb_4xx_errors.alarm_name],
    [aws_cloudwatch_metric_alarm.alb_low_request_count.alarm_name],
    
    # Application Alarms
    [for alarm in aws_cloudwatch_metric_alarm.application_errors : alarm.alarm_name],
    try([aws_cloudwatch_metric_alarm.flask_5xx_errors[0].alarm_name], [])
  )
}

output "critical_alarms" {
  description = "List of critical alarm names (service health related)"
  value = concat(
    [for alarm in aws_cloudwatch_metric_alarm.ecs_low_task_count : alarm.alarm_name],
    [for alarm in aws_cloudwatch_metric_alarm.alb_unhealthy_targets : alarm.alarm_name],
    [aws_cloudwatch_metric_alarm.alb_5xx_errors.alarm_name],
    try([aws_cloudwatch_metric_alarm.flask_5xx_errors[0].alarm_name], [])
  )
}

output "performance_alarms" {
  description = "List of performance-related alarm names"
  value = concat(
    [for alarm in aws_cloudwatch_metric_alarm.ecs_high_cpu : alarm.alarm_name],
    [for alarm in aws_cloudwatch_metric_alarm.ecs_high_memory : alarm.alarm_name],
    [for alarm in aws_cloudwatch_metric_alarm.alb_high_response_time : alarm.alarm_name]
  )
}

output "composite_alarms" {
  description = "List of composite alarm names for service health"
  value       = [for alarm in aws_cloudwatch_composite_alarm.service_health : alarm.alarm_name]
}

# ============================================================================
# METRIC FILTER INFORMATION
# ============================================================================

output "metric_filter_names" {
  description = "Names of all metric filters created"
  value = concat(
    [aws_cloudwatch_log_metric_filter.ecs_task_failures.name],
    [aws_cloudwatch_log_metric_filter.ecs_service_events.name],
    [for filter in aws_cloudwatch_log_metric_filter.app_errors : filter.name],
    [for filter in aws_cloudwatch_log_metric_filter.app_warnings : filter.name],
    try([aws_cloudwatch_log_metric_filter.flask_5xx_errors[0].name], [])
  )
}

# ============================================================================
# MONITORING CONFIGURATION SUMMARY
# ============================================================================

output "monitoring_summary" {
  description = "Summary of monitoring configuration"
  value = {
    cluster_name    = var.cluster_name
    applications    = keys(var.applications)
    total_alarms    = length(concat(
      [for alarm in aws_cloudwatch_metric_alarm.ecs_high_cpu : alarm.alarm_name],
      [for alarm in aws_cloudwatch_metric_alarm.ecs_high_memory : alarm.alarm_name],
      [for alarm in aws_cloudwatch_metric_alarm.ecs_low_task_count : alarm.alarm_name],
      [for alarm in aws_cloudwatch_metric_alarm.alb_high_response_time : alarm.alarm_name],
      [for alarm in aws_cloudwatch_metric_alarm.alb_unhealthy_targets : alarm.alarm_name],
      [aws_cloudwatch_metric_alarm.alb_5xx_errors.alarm_name],
      [aws_cloudwatch_metric_alarm.alb_4xx_errors.alarm_name],
      [aws_cloudwatch_metric_alarm.alb_low_request_count.alarm_name],
      [for alarm in aws_cloudwatch_metric_alarm.application_errors : alarm.alarm_name],
      try([aws_cloudwatch_metric_alarm.flask_5xx_errors[0].alarm_name], [])
    ))
    total_metric_filters = length(concat(
      [aws_cloudwatch_log_metric_filter.ecs_task_failures.name],
      [aws_cloudwatch_log_metric_filter.ecs_service_events.name],
      [for filter in aws_cloudwatch_log_metric_filter.app_errors : filter.name],
      [for filter in aws_cloudwatch_log_metric_filter.app_warnings : filter.name],
      try([aws_cloudwatch_log_metric_filter.flask_5xx_errors[0].name], [])
    ))
    notification_emails = var.notification_emails
    log_retention_days  = var.log_retention_days
  }
}

# ============================================================================
# LOG INSIGHTS QUERIES
# ============================================================================

output "log_insights_queries" {
  description = "Pre-built CloudWatch Insights queries for troubleshooting"
  value = {
    ecs_task_failures = "SOURCE '${aws_cloudwatch_log_group.ecs_events.name}' | fields @timestamp, @message | filter @message like /STOPPED/ or @message like /FAILED/ | sort @timestamp desc | limit 100"
    
    application_errors = {
      for k, v in aws_cloudwatch_log_group.app_logs : k => "SOURCE '${v.name}' | fields @timestamp, @message | filter @message like /ERROR/ | sort @timestamp desc | limit 100"
    }
    
    alb_errors = "SOURCE '${aws_cloudwatch_log_group.alb_logs.name}' | fields @timestamp, @message | filter @message like /5\\d\\d/ | sort @timestamp desc | limit 100"
    
    performance_issues = "SOURCE '${aws_cloudwatch_log_group.ecs_events.name}' | fields @timestamp, @message | filter @message like /OutOfMemory/ or @message like /HealthCheck/ | sort @timestamp desc | limit 50"
  }
}

# ============================================================================
# SECURITY AND COMPLIANCE OUTPUTS
# ============================================================================

output "security_monitoring_enabled" {
  description = "Security monitoring features enabled"
  value = {
    cloudtrail_logging    = "Configure CloudTrail for API monitoring"
    vpc_flow_logs        = "Configure VPC Flow Logs for network monitoring"
    config_rules         = "Configure AWS Config for compliance monitoring"
    guardduty            = "Enable GuardDuty for threat detection"
    security_hub         = "Enable Security Hub for security posture"
  }
}

output "cost_monitoring_recommendations" {
  description = "Cost monitoring recommendations"
  value = {
    cost_explorer        = "Use AWS Cost Explorer for cost analysis"
    budgets             = "Set up AWS Budgets for cost control"
    trusted_advisor     = "Use Trusted Advisor for cost optimization"
    cost_anomaly_detection = "Enable Cost Anomaly Detection for unusual spending"
  }
}
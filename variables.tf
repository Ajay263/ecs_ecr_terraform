# variables.tf - Root Module Variable Declarations

# ============================================================================
# NOTIFICATION CONFIGURATION
# ============================================================================

variable "notification_emails" {
  description = "List of email addresses to receive monitoring alerts"
  type        = list(string)
  default     = []
}

variable "critical_notification_emails" {
  description = "Email addresses for critical alerts (service outages, security issues)"
  type        = list(string)
  default     = []
}

variable "warning_notification_emails" {
  description = "Email addresses for warning alerts (performance degradation)"
  type        = list(string)
  default     = []
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for notifications (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "pagerduty_integration_key" {
  description = "PagerDuty integration key for critical alerts (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

# ============================================================================
# ECS MONITORING THRESHOLDS
# ============================================================================

variable "cpu_threshold" {
  description = "CPU utilization threshold for alarms (percentage)"
  type        = number
  default     = 80
}

variable "memory_threshold" {
  description = "Memory utilization threshold for alarms (percentage)"
  type        = number
  default     = 80
}

variable "task_count_threshold" {
  description = "Minimum number of running tasks before alarm"
  type        = number
  default     = 1
}

# ============================================================================
# ALB MONITORING THRESHOLDS
# ============================================================================

variable "alb_response_time_threshold" {
  description = "ALB response time threshold in seconds"
  type        = number
  default     = 2.0
}

variable "alb_5xx_threshold" {
  description = "ALB 5xx error count threshold per 5 minutes"
  type        = number
  default     = 5
}

variable "alb_4xx_threshold" {
  description = "ALB 4xx error count threshold per 5 minutes"
  type        = number
  default     = 50
}

variable "alb_low_traffic_threshold" {
  description = "Minimum request count to avoid low traffic alarm"
  type        = number
  default     = 10
}

# ============================================================================
# APPLICATION MONITORING THRESHOLDS
# ============================================================================

variable "error_threshold" {
  description = "Application error count threshold per 5 minutes"
  type        = number
  default     = 5
}

variable "flask_5xx_threshold" {
  description = "Flask API 5xx error count threshold per 5 minutes"
  type        = number
  default     = 3
}

variable "warning_threshold" {
  description = "Application warning count threshold per 5 minutes"
  type        = number
  default     = 10
}

# ============================================================================
# LOG RETENTION AND MONITORING FEATURES
# ============================================================================

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring (1-minute metrics)"
  type        = bool
  default     = true
}

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights for enhanced ECS monitoring"
  type        = bool
  default     = true
}

variable "enable_cost_anomaly_detection" {
  description = "Enable AWS Cost Anomaly Detection for cost monitoring"
  type        = bool
  default     = true
}

# ============================================================================
# ENVIRONMENT CONFIGURATION
# ============================================================================

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "mtc-app"
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}
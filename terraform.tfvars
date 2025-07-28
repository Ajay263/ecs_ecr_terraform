# terraform.tfvars - Enhanced Monitoring Configuration

# ============================================================================
# NOTIFICATION CONFIGURATION
# ============================================================================

# Primary notification emails (receive all alerts)
notification_emails = [
  "junioralexio607@gmail.com"
]

# Critical alerts only (service outages, security issues)
critical_notification_emails = [
  "junioralexio607@gmail.com"
]

# Warning alerts (performance degradation, high resource usage)
warning_notification_emails = [
  "junioralexio607@gmail.com"
]

# Optional: Slack webhook for team notifications
# slack_webhook_url = "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"

# Optional: PagerDuty for critical alerts
# pagerduty_integration_key = "your-pagerduty-integration-key"

# ============================================================================
# ECS MONITORING THRESHOLDS
# ============================================================================

# CPU utilization threshold (percentage)
cpu_threshold = 75

# Memory utilization threshold (percentage) 
memory_threshold = 80

# Minimum number of running tasks before alarm
task_count_threshold = 1

# ============================================================================
# ALB MONITORING THRESHOLDS
# ============================================================================

# ALB response time threshold in seconds
alb_response_time_threshold = 2.0

# ALB 5xx error count threshold per 5 minutes
alb_5xx_threshold = 3

# ALB 4xx error count threshold per 5 minutes
alb_4xx_threshold = 25

# Minimum request count to avoid low traffic alarm
alb_low_traffic_threshold = 5

# ============================================================================
# APPLICATION MONITORING THRESHOLDS
# ============================================================================

# Application error count threshold per 5 minutes
error_threshold = 3

# Flask API specific 5xx error threshold per 5 minutes
flask_5xx_threshold = 2

# Application warning count threshold per 5 minutes
warning_threshold = 10

# ============================================================================
# LOG RETENTION AND MONITORING FEATURES
# ============================================================================

# Log retention period in days
log_retention_days = 14

# Enable detailed CloudWatch monitoring (1-minute metrics)
enable_detailed_monitoring = true

# Enable CloudWatch Container Insights for enhanced ECS monitoring
enable_container_insights = true

# Enable AWS Cost Anomaly Detection
enable_cost_anomaly_detection = true

# ============================================================================
# ENVIRONMENT CONFIGURATION
# ============================================================================

# Environment name (affects alarm sensitivity)
environment = "dev"

# Project name for resource naming
project_name = "mtc-app"

# AWS Region
aws_region = "us-east-1"

# ============================================================================
# MONITORING RECOMMENDATIONS BY ENVIRONMENT
# ============================================================================

# Development Environment (Current Settings):
# - Lower thresholds for early detection
# - More aggressive monitoring for debugging
# - Shorter log retention to control costs

# Production Environment (Recommended Changes):
# cpu_threshold = 80
# memory_threshold = 85
# alb_response_time_threshold = 1.0
# alb_5xx_threshold = 1
# error_threshold = 1
# flask_5xx_threshold = 1
# log_retention_days = 30
# critical_notification_emails = ["oncall@company.com", "devops@company.com"]

# Staging Environment (Recommended Changes):
# cpu_threshold = 78
# memory_threshold = 82
# alb_5xx_threshold = 2
# error_threshold = 2
# log_retention_days = 21
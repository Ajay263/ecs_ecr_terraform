# main.tf (Updated with proper variable passing)

# Data sources
data "aws_secretsmanager_secret" "groq_api_key" {
  name = "groqkey"
}

data "aws_region" "current" {}

# Local values
locals {
  apps = {
    ui = {
      ecr_repository_name = "ui"
      app_path            = "ui"
      image_version       = "1.0.1"
      app_name            = "ui"
      port                = 80
      cpu                 = 256
      memory              = 512
      desired_count       = 1
      is_public           = true
      path_pattern        = "/*"
      lb_priority         = 20
      healthcheck_path    = "/"
      healthcheck_command = ["CMD-SHELL", "curl -f http://localhost/ || exit 1"]
      secrets             = []
      envars              = []
    }
    api = {
      ecr_repository_name = "api"
      app_path            = "api"
      image_version       = "1.0.4"
      app_name            = "api"
      port                = 5000
      cpu                 = 512
      memory              = 1024
      desired_count       = 2
      is_public           = true
      path_pattern        = "/api/*"
      lb_priority         = 10
      healthcheck_path    = "/api/healthcheck"
      healthcheck_command = ["CMD-SHELL", "curl -f http://localhost:5000/api/healthcheck || exit 1"]
      secrets = [
        {
          name      = "GROQ_API_KEY"
          valueFrom = data.aws_secretsmanager_secret.groq_api_key.arn
        }
      ]
      envars = []
    }
  }

  # Environment-specific configuration
  environment = terraform.workspace == "default" ? "dev" : terraform.workspace

  common_tags = {
    Environment = local.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
  }
}

# Infrastructure module
module "infra" {
  source      = "./modules/infra"
  vpc_cidr    = "10.0.0.0/16"
  num_subnets = 3
  allowed_ips = ["0.0.0.0/0"]
}

# Generate Dockerfile for UI with backend URL
resource "local_file" "dockerfile" {
  content = templatefile("modules/app/apps/templates/ui.tftpl", {
    build_args = {
      "backend_url" = module.infra.alb_dns_name
    }
  })
  filename = "modules/app/apps/ui/Dockerfile"
}

# Application modules
module "app" {
  source = "./modules/app"

  for_each = local.apps

  depends_on = [local_file.dockerfile]

  # Application configuration
  ecr_repository_name = each.value.ecr_repository_name
  app_path            = each.value.app_path
  image_version       = each.value.image_version
  app_name            = each.value.app_name
  port                = each.value.port
  cpu                 = each.value.cpu
  memory              = each.value.memory
  desired_count       = each.value.desired_count
  is_public           = each.value.is_public
  path_pattern        = each.value.path_pattern
  envars              = each.value.envars
  secrets             = each.value.secrets
  healthcheck_path    = each.value.healthcheck_path
  healthcheck_command = each.value.healthcheck_command
  lb_priority         = each.value.lb_priority

  # Infrastructure references
  execution_role_arn    = module.infra.execution_role_arn
  app_security_group_id = module.infra.app_security_group_id
  subnets               = module.infra.public_subnets
  cluster_arn           = module.infra.cluster_arn
  vpc_id                = module.infra.vpc_id
  alb_listener_arn      = module.infra.alb_listener_arn

  # Monitoring configuration - will be set after monitoring module is created
  log_group_name = "/ecs/${module.infra.cluster_name}/${each.key}"
  aws_region     = data.aws_region.current.name

  tags = local.common_tags
}

# Monitoring module
module "monitoring" {
  source = "./modules/monitoring"

  depends_on = [module.infra]

  # Cluster configuration
  cluster_name = module.infra.cluster_name
  cluster_arn  = module.infra.cluster_arn

  # Applications to monitor
  applications = {
    for app_name, app_config in local.apps : app_name => {
      name = app_config.app_name
    }
  }

  # Target groups for ALB monitoring
  target_groups = {
    for app_name, app in module.app : app_name => app.target_group_arn_suffix
  }

  # Load balancer configuration
  load_balancer_arn_suffix = module.infra.alb_arn_suffix

  # Pass all variables from root module to monitoring module
  notification_emails                = var.notification_emails
  critical_notification_emails       = var.critical_notification_emails
  warning_notification_emails        = var.warning_notification_emails
  slack_webhook_url                  = var.slack_webhook_url
  pagerduty_integration_key          = var.pagerduty_integration_key
  
  # Monitoring thresholds
  cpu_threshold                      = var.cpu_threshold
  memory_threshold                   = var.memory_threshold
  task_count_threshold               = var.task_count_threshold
  alb_response_time_threshold        = var.alb_response_time_threshold
  alb_5xx_threshold                  = var.alb_5xx_threshold
  alb_4xx_threshold                  = var.alb_4xx_threshold
  alb_low_traffic_threshold          = var.alb_low_traffic_threshold
  error_threshold                    = var.error_threshold
  flask_5xx_threshold                = var.flask_5xx_threshold
  warning_threshold                  = var.warning_threshold
  
  # Configuration options
  log_retention_days                 = var.log_retention_days
  enable_detailed_monitoring         = var.enable_detailed_monitoring
  enable_container_insights          = var.enable_container_insights
  enable_cost_anomaly_detection      = var.enable_cost_anomaly_detection
  environment                        = var.environment
  project_name                       = var.project_name

  tags = local.common_tags
}

# CloudWatch log insights saved queries
resource "aws_cloudwatch_query_definition" "ecs_errors" {
  name = "${module.infra.cluster_name}-ecs-errors"

  log_group_names = [
    module.monitoring.cloudwatch_log_groups.ecs_events
  ]

  query_string = <<EOF
fields @timestamp, detail.group, detail.stopCode, detail.stoppedReason, detail.containers
| filter detail.stopCode = "TaskFailedToStart" or detail.stopCode = "TaskFailed"
| sort @timestamp desc
| limit 100
EOF
}

resource "aws_cloudwatch_query_definition" "app_errors" {
  for_each = local.apps

  name = "${module.infra.cluster_name}-${each.key}-errors"

  log_group_names = [
    module.monitoring.cloudwatch_log_groups.app_logs[each.key]
  ]

  query_string = <<EOF
fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 100
EOF
}

# Outputs
output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = "http://${module.infra.alb_dns_name}"
}

output "monitoring_dashboard_url" {
  description = "URL to the CloudWatch monitoring dashboard"
  value       = module.monitoring.dashboard_url
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for monitoring alerts"
  value       = module.monitoring.sns_topic_arn
}

output "application_services" {
  description = "Information about deployed application services"
  value = {
    for app_name, app in module.app : app_name => {
      service_name = app.service_name
      service_arn  = app.service_arn
      ecr_url      = app.ecr_repository_url
    }
  }
}

output "alarm_names" {
  description = "List of all CloudWatch alarm names"
  value       = module.monitoring.alarm_names
}

output "monitoring_summary" {
  description = "Comprehensive monitoring setup summary"
  value       = module.monitoring.monitoring_summary
}

output "security_monitoring" {
  description = "Security monitoring resources"
  value = {
    cloudtrail_enabled = true
    vpc_flow_logs_enabled = true
    security_alarms_count = 3
  }
}
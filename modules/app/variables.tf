# modules/app/variables.tf (Updated)

variable "ecr_repository_name" {
  description = "Name of the ECR repository"
  type        = string
}

variable "app_path" {
  description = "Path to the application directory"
  type        = string
}

variable "image_version" {
  description = "Version/tag of the Docker image"
  type        = string
}

variable "app_name" {
  description = "Name of the application"
  type        = string
}

variable "port" {
  description = "Port the application listens on"
  type        = number
}

variable "cpu" {
  description = "CPU units for the ECS task"
  type        = number
  default     = 256
}

variable "memory" {
  description = "Memory (in MB) for the ECS task"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of desired instances of the task"
  type        = number
  default     = 1
}

variable "execution_role_arn" {
  description = "ARN of the ECS task execution role"
  type        = string
}

variable "task_role_arn" {
  description = "ARN of the ECS task role"
  type        = string
  default     = null
}

variable "app_security_group_id" {
  description = "Security group ID for the application"
  type        = string
}

variable "subnets" {
  description = "List of subnet IDs"
  type        = list(string)
}

variable "is_public" {
  description = "Whether to assign public IP to tasks"
  type        = bool
  default     = true
}

variable "cluster_arn" {
  description = "ARN of the ECS cluster"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "alb_listener_arn" {
  description = "ARN of the ALB listener"
  type        = string
}

variable "path_pattern" {
  description = "Path pattern for ALB routing"
  type        = string
  default     = "/*"
}

variable "healthcheck_path" {
  description = "Health check path for the target group"
  type        = string
  default     = "/"
}

variable "healthcheck_command" {
  description = "Health check command for the container"
  type        = list(string)
  default     = null
}

variable "envars" {
  description = "Environment variables for the container"
  type        = list(map(string))
  default     = []
}

variable "secrets" {
  description = "Secrets for the container"
  type        = list(map(string))
  default     = []
}

variable "lb_priority" {
  description = "Priority for the load balancer rule"
  type        = number
}

variable "log_group_name" {
  description = "CloudWatch log group name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
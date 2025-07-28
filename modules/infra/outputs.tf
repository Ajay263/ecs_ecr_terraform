# modules/infra/outputs.tf (Updated)

output "execution_role_arn" {
  description = "ARN of the ECS execution role"
  value       = aws_iam_role.ecs_execution_role.arn
}

output "app_security_group_id" {
  description = "Security group ID for applications"
  value       = aws_security_group.app.id
}

output "public_subnets" {
  description = "List of public subnet IDs"
  value       = [for i in aws_subnet.this : i.id]
}

output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.this.arn
}

output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.this.name
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.this.id
}

output "alb_listener_arn" {
  description = "ARN of the ALB listener"
  value       = aws_lb_listener.this.arn
}

output "alb_dns_name" {
  description = "DNS name of the ALB"
  value       = aws_lb.this.dns_name
}

output "alb_arn" {
  description = "ARN of the ALB"
  value       = aws_lb.this.arn
}

output "alb_arn_suffix" {
  description = "ARN suffix of the ALB"
  value       = aws_lb.this.arn_suffix
}
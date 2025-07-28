# modules/app/main.tf (Updated with logging configuration)

locals {
  ecr_url   = aws_ecr_repository.this.repository_url
  ecr_token = data.aws_ecr_authorization_token.this
}

data "aws_ecr_authorization_token" "this" {}

resource "aws_ecr_repository" "this" {
  name         = var.ecr_repository_name
  force_delete = true

  tags = var.tags
}

resource "terraform_data" "login" {
  provisioner "local-exec" {
    command = <<EOT
        docker login ${local.ecr_url} \
        --username ${local.ecr_token.user_name} \
        --password ${local.ecr_token.password}
        EOT
  }
}

resource "terraform_data" "build" {
  triggers_replace = [
    var.image_version
  ]
  depends_on = [terraform_data.login]
  provisioner "local-exec" {
    command = <<EOT
        docker build -t ${local.ecr_url} ${path.module}/apps/${var.app_path}
        EOT
  }
}

resource "terraform_data" "push" {
  triggers_replace = [
    var.image_version
  ]
  depends_on = [terraform_data.login, terraform_data.build]
  provisioner "local-exec" {
    command = <<EOT
        docker image tag ${local.ecr_url} ${local.ecr_url}:${var.image_version}
        docker image tag ${local.ecr_url} ${local.ecr_url}:latest
        docker image push ${local.ecr_url}:${var.image_version}
        docker image push ${local.ecr_url}:latest
        EOT
  }
}

resource "aws_ecs_task_definition" "this" {
  family                   = "${var.app_name}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([
    {
      name        = var.app_name
      image       = "${local.ecr_url}:${var.image_version}"
      cpu         = var.cpu
      memory      = var.memory
      essential   = true
      environment = var.envars
      secrets     = var.secrets
      
      portMappings = [
        {
          containerPort = var.port
          hostPort      = var.port
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.log_group_name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      healthCheck = var.healthcheck_command != null ? {
        command     = var.healthcheck_command
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      } : null
    }
  ])

  tags = var.tags
}

resource "aws_ecs_service" "this" {
  name            = "${var.app_name}-service"
  cluster         = var.cluster_arn
  task_definition = aws_ecs_task_definition.this.arn
  launch_type     = "FARGATE"
  desired_count   = var.desired_count



  network_configuration {
    subnets          = var.subnets
    security_groups  = [var.app_security_group_id]
    assign_public_ip = var.is_public
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = var.app_name
    container_port   = var.port
  }

  depends_on = [aws_lb_target_group.this]

  tags = var.tags
}

resource "aws_lb_target_group" "this" {
  name                 = "${var.app_name}-tg"
  port                 = var.port
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = 30

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = var.healthcheck_path
    matcher             = "200"
    protocol            = "HTTP"
  }

  tags = var.tags
}

resource "aws_lb_listener_rule" "http_rule" {
  listener_arn = var.alb_listener_arn
  priority     = var.lb_priority

  condition {
    path_pattern {
      values = [var.path_pattern]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  tags = var.tags
}
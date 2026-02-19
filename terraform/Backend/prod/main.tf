################################
# VARIABLES
################################

variable "environment" {
  default = "prod"
}

################################
# DATA SOURCES
################################

data "aws_caller_identity" "current" {}

data "aws_vpc" "shared" {
  filter {
    name   = "cidr-block"
    values = ["10.0.0.0/16"]
  }
}

# Public subnets for ALB
data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.shared.id]
  }

  filter {
    name   = "tag:Type"
    values = ["public"]
  }
}

# ✅ Private subnets for ECS (PROD)
data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.shared.id]
  }

  filter {
    name   = "cidr-block"
    values = ["10.0.2.0/24", "10.0.3.0/24"]
  }
}

data "aws_ecs_cluster" "shared" {
  cluster_name = "shared-ecs-cluster"
}

################################
# SECURITY GROUPS
################################

resource "aws_security_group" "alb_sg" {
  name   = "alb-${var.environment}-sg"
  vpc_id = data.aws_vpc.shared.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs_sg" {
  name   = "ecs-${var.environment}-sg"
  vpc_id = data.aws_vpc.shared.id

  ingress {
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

################################
# ECR
################################

resource "aws_ecr_repository" "repo" {
  name = "backend-${var.environment}"
}

################################
# ALB
################################

resource "aws_lb" "alb" {
  name               = "backend-${var.environment}-alb"
  load_balancer_type = "application"
  subnets            = data.aws_subnets.public.ids
  security_groups    = [aws_security_group.alb_sg.id]
}

################################
# TARGET GROUP
################################

resource "aws_lb_target_group" "tg" {
  name        = "tg-${var.environment}"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.shared.id
  target_type = "ip"

  health_check {
    path = "/api/health"
  }
}

################################
# LISTENER
################################

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

################################
# IAM ROLE
################################

resource "aws_iam_role" "ecs_execution_role" {
  name = "ecsTaskExecutionRole-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
# TASK DEFINITION
resource "aws_ecs_task_definition" "task" {
  family                   = "backend-${var.environment}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "1024"
  memory                   = "2048"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([{
    name      = "backend"
    image     = "${data.aws_caller_identity.current.account_id}.dkr.ecr.ap-south-1.amazonaws.com/backend-${var.environment}:latest"
    essential = true

    portMappings = [{
      containerPort = 8000
      hostPort      = 8000
    }]
  }])
}

# ECS SERVICE
resource "aws_ecs_service" "service" {
  name            = "backend-${var.environment}-service"
  cluster         = data.aws_ecs_cluster.shared.id
  task_definition = aws_ecs_task_definition.task.arn
  desired_count   = 3   # ✅ Minimum running tasks

  launch_type = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.private.ids
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.tg.arn
    container_name   = "backend"
    container_port   = 8000
  }

  depends_on = [aws_lb_listener.http]
}
# AUTO SCALING TARGET

resource "aws_appautoscaling_target" "ecs_target" {
  max_capacity       = 20
  min_capacity       = 3
  resource_id        = "service/${data.aws_ecs_cluster.shared.cluster_name}/${aws_ecs_service.service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}
# AUTO SCALING POLICY (CPU BASED)

resource "aws_appautoscaling_policy" "ecs_cpu_policy" {
  name               = "ecs-cpu-scaling-${var.environment}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = 60.0

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    scale_in_cooldown  = 120
    scale_out_cooldown = 60
  }
}

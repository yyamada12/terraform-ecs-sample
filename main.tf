provider "aws" {
  region = "ap-northeast-1"
  #   .envrc で設定
  #   export AWS_ACCESS_KEY_ID="your_access_key"
  #   export AWS_SECRET_ACCESS_KEY="your_secret_key"
  # 
  #   or ベタがき
  #   access_key = "your_access_key"
  #   secret_key = "your_secret_key"
}


####################################################
# data source
####################################################
data "aws_vpc" "yyamada-vpc" {

  filter {
    name   = "tag:Name"
    values = ["vpc-yyamada"]
  }
}

data "aws_subnets" "public-subnets" {
  filter {
    name   = "tag:Name"
    values = ["yyamada-public-subnet-*"]
  }
}

####################################################
# ECS Cluster
####################################################
resource "aws_ecs_cluster" "nginx_cluster" {
  name = "nginx-cluster"
}

####################################################
# IAM Role for ECS task execution
####################################################

// ECS エージェントが ECS タスクを実行するときに使用する IAM ロール
// ECS (ecs-tasks.amazonaws.com) が AssumeRoleし、AmazonECSTaskExecutionRolePolicy を利用する
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs_task_execution_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  ]
}

####################################################
# CloudWatch Log Groups for ECS task
####################################################

resource "aws_cloudwatch_log_group" "nginx-sample" {
  name              = "/ecs/nginx-sample"
  retention_in_days = 30
}


####################################################
# ECS Task Definition
####################################################

resource "aws_ecs_task_definition" "nginx-sample" {
  family                   = "nginx-sample"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn // ECSエージェントがECSタスクを実行するときに使用するIAMロールを指定する
  task_role_arn            = aws_iam_role.ecs_task_execution_role.arn // アプリケーションが必要な権限を持つIAMロールを指定する
  container_definitions = jsonencode([
    {
      name         = "nginx-sample"
      image        = "nginx"
      portMappings = [{ containerPort : 80 }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-region : "ap-northeast-1"
          awslogs-group : aws_cloudwatch_log_group.nginx-sample.name
          awslogs-stream-prefix : "ecs"
        }
      }
    }
  ])
}

####################################################
# ALB
####################################################

# ALB本体
resource "aws_lb" "nginx-sample" {
  name                       = "ecs-sample-alb"
  load_balancer_type         = "application"
  internal                   = false
  idle_timeout               = 60
  enable_deletion_protection = false

  subnets = data.aws_subnets.public-subnets.ids

  security_groups = [
    aws_security_group.nginx-sample-alb-sg.id
  ]
}

// 80番ポートで受け取ったリクエストをターゲットグループにフォワードするリスナー
resource "aws_alb_listener" "nginx-sample" {
  load_balancer_arn = aws_lb.nginx-sample.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nginx-sample.arn
  }
}

// ALBのターゲットグループ
// ECS Service で指定することにより、タスクでコンテナが起動するとターゲットに登録される
resource "aws_lb_target_group" "nginx-sample" {
  name                 = "ecs-nginx-sample-target-group"
  vpc_id               = data.aws_vpc.yyamada-vpc.id
  target_type          = "ip"
  port                 = 80
  protocol             = "HTTP"
  deregistration_delay = 300

  health_check {
    path                = "/"
    healthy_threshold   = 5
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    matcher             = 200
    port                = "traffic-port"
    protocol            = "HTTP"
  }

  depends_on = [aws_lb.nginx-sample]
}


resource "aws_security_group" "nginx-sample-alb-sg" {
  name = "nginx-sample-alb-sg"

  vpc_id = data.aws_vpc.yyamada-vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # 特定のIPアドレスを指定
  }

}

####################################################
# ECS Service
####################################################

resource "aws_ecs_service" "nginx-sample" {
  name                               = "nginx-sample-service"
  cluster                            = aws_ecs_cluster.nginx_cluster.id
  platform_version                   = "LATEST"
  task_definition                    = aws_ecs_task_definition.nginx-sample.arn
  desired_count                      = 1
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  propagate_tags                     = "SERVICE"
  enable_execute_command             = true
  launch_type                        = "FARGATE"
  health_check_grace_period_seconds  = 60
  network_configuration {
    # public subnet に配置する場合は true にする必要がある ref: https://docs.aws.amazon.com/ja_jp/AmazonECS/latest/developerguide/task_cannot_pull_image.html
    assign_public_ip = true
    subnets          = data.aws_subnets.public-subnets.ids
    security_groups = [
      aws_security_group.nginx-sample-task-sg.id
    ]
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.nginx-sample.arn
    container_name   = "nginx-sample"
    container_port   = 80
  }
}

resource "aws_security_group" "nginx-sample-task-sg" {
  name = "nginx-sample-task-sg"

  vpc_id = data.aws_vpc.yyamada-vpc.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.nginx-sample-alb-sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}


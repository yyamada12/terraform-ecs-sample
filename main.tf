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
# ECS Cluster
####################################################
resource "aws_ecs_cluster" "nginx_cluster" {
  name = "nginx-cluster"
}


####################################################
# ECS IAM Role
####################################################

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
# ECS Task Container Log Groups
####################################################

resource "aws_cloudwatch_log_group" "nginx-sample" {
  name              = "/ecs/nginx-sample"
  retention_in_days = 30
}


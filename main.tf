provider "aws" {
  region  = "ap-northeast-1"
#   .envrc で設定
#   export AWS_ACCESS_KEY_ID="your_access_key"
#   export AWS_SECRET_ACCESS_KEY="your_secret_key"
# 
#   or ベタがき
#   access_key = "your_access_key"
#   secret_key = "your_secret_key"
}

resource "aws_ecs_cluster" "nginx_cluster" {
  name = "nginx-cluster"
}

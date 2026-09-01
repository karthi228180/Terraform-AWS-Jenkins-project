########################################
# App EC2 instance role
#   - pull images from ECR
#   - read its own DB creds from SSM Parameter Store (only its own path)
#   - ship metrics/logs to CloudWatch
#   - be reachable via SSM Session Manager instead of open SSH
########################################

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "app_ec2" {
  name = "${var.project_name}-${var.environment}-app-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "app_ec2_ssm_core" {
  role       = aws_iam_role.app_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "app_ec2_cw_agent" {
  role       = aws_iam_role.app_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy" "app_ec2_ecr_pull" {
  name = "${var.project_name}-${var.environment}-ecr-pull"
  role = aws_iam_role.app_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability"
        ]
        Resource = [
          local.app_tier_repo_arn,
          local.web_tier_repo_arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "app_ec2_ssm_params" {
  name = "${var.project_name}-${var.environment}-ssm-read"
  role = aws_iam_role.app_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
      Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_name}/${var.environment}/*"
    }]
  })
}

resource "aws_iam_role_policy" "app_ec2_deploy_artifacts_read" {
  name = "${var.project_name}-${var.environment}-deploy-artifacts-read"
  role = aws_iam_role.app_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = "${local.deploy_artifacts_arn}/${var.environment}/*"
    }]
  })
}

resource "aws_iam_instance_profile" "app_ec2" {
  name = "${var.project_name}-${var.environment}-app-ec2-profile"
  role = aws_iam_role.app_ec2.name
}

########################################
# Jenkins host role
#   - push/pull images to/from ECR
#   - trigger deploys on app instances via SSM Run Command
#   - describe EC2 instances (to target them by tag)
########################################

resource "aws_iam_role" "jenkins" {
  count = var.is_primary_environment ? 1 : 0
  name  = "${var.project_name}-jenkins-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "jenkins_ssm_core" {
  count      = var.is_primary_environment ? 1 : 0
  role       = aws_iam_role.jenkins[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "jenkins_ecr_push" {
  count = var.is_primary_environment ? 1 : 0
  name  = "${var.project_name}-jenkins-ecr-push"
  role  = aws_iam_role.jenkins[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = [
          local.app_tier_repo_arn,
          local.web_tier_repo_arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "jenkins_deploy" {
  count = var.is_primary_environment ? 1 : 0
  name  = "${var.project_name}-jenkins-deploy"
  role  = aws_iam_role.jenkins[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:SendCommand",
          "ssm:GetCommandInvocation",
          "ssm:ListCommandInvocations"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "jenkins_deploy_artifacts_write" {
  count = var.is_primary_environment ? 1 : 0
  name  = "${var.project_name}-jenkins-deploy-artifacts-write"
  role  = aws_iam_role.jenkins[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject"]
      Resource = "${local.deploy_artifacts_arn}/*"
    }]
  })
}

resource "aws_iam_instance_profile" "jenkins" {
  count = var.is_primary_environment ? 1 : 0
  name  = "${var.project_name}-jenkins-profile"
  role  = aws_iam_role.jenkins[0].name
}

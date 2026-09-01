########################################
# ECR repositories - shared across environments (Jenkins builds one image
# and promotes the SAME tag from staging to production).
#
# Set is_primary_environment = true in exactly ONE environment (typically staging,
# applied first). Every other environment leaves it false and just looks
# the repos up by name.
########################################

resource "aws_ecr_repository" "app_tier" {
  count                = var.is_primary_environment ? 1 : 0
  name                 = "${var.project_name}-app-tier"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = "${var.project_name}-app-tier" }
}

resource "aws_ecr_repository" "web_tier" {
  count                = var.is_primary_environment ? 1 : 0
  name                 = "${var.project_name}-web-tier"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = "${var.project_name}-web-tier" }
}

resource "aws_ecr_lifecycle_policy" "app_tier" {
  count      = var.is_primary_environment ? 1 : 0
  repository = aws_ecr_repository.app_tier[0].name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 20 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 20 }
      action       = { type = "expire" }
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "web_tier" {
  count      = var.is_primary_environment ? 1 : 0
  repository = aws_ecr_repository.web_tier[0].name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 20 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 20 }
      action       = { type = "expire" }
    }]
  })
}

# Environments that don't manage the repos (is_primary_environment = false)
# look them up here instead -- they must already exist
# up here instead -- they must already exist (created by the one
# environment that does manage them).
data "aws_ecr_repository" "app_tier_existing" {
  count = var.is_primary_environment ? 0 : 1
  name  = "${var.project_name}-app-tier"
}

data "aws_ecr_repository" "web_tier_existing" {
  count = var.is_primary_environment ? 0 : 1
  name  = "${var.project_name}-web-tier"
}

locals {
  app_tier_repo_url = var.is_primary_environment ? aws_ecr_repository.app_tier[0].repository_url : data.aws_ecr_repository.app_tier_existing[0].repository_url
  app_tier_repo_arn = var.is_primary_environment ? aws_ecr_repository.app_tier[0].arn : data.aws_ecr_repository.app_tier_existing[0].arn
  web_tier_repo_url = var.is_primary_environment ? aws_ecr_repository.web_tier[0].repository_url : data.aws_ecr_repository.web_tier_existing[0].repository_url
  web_tier_repo_arn = var.is_primary_environment ? aws_ecr_repository.web_tier[0].arn : data.aws_ecr_repository.web_tier_existing[0].arn
}

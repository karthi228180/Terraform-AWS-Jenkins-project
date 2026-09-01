########################################
# Deploy artifacts bucket (shared, owned by the primary environment)
#   Jenkins uploads scripts/deploy.sh to s3://<bucket>/<environment>/deploy.sh
#   on every deploy; app instances in that environment pull it down via SSM
#   Run Command. One bucket, per-environment key prefixes -- avoids the
#   cross-environment IAM/state problems a per-environment bucket would cause.
########################################

/*
resource "aws_s3_bucket_public_access_block" "deploy_artifacts" {
  count                   = var.is_primary_environment ? 1 : 0
  bucket                  = aws_s3_bucket.deploy_artifacts[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "deploy_artifacts" {
  count  = var.is_primary_environment ? 1 : 0
  bucket = aws_s3_bucket.deploy_artifacts.id
  versioning_configuration { status = "Enabled" }
}

data "aws_s3_bucket" "deploy_artifacts_existing" {
  count  = var.is_primary_environment ? 0 : 1
  bucket = "${var.project_name}-deploy-artifacts-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "deploy_artifacts" {
  bucket = "${var.project_name}-deploy-artifacts-${data.aws_caller_identity.current.account_id}"
}

locals {
  deploy_artifacts_bucket = var.is_primary_environment ? aws_s3_bucket.deploy_artifacts[0].id : aws_s3_bucket.deploy_artifacts.id
  deploy_artifacts_arn    = var.is_primary_environment ? aws_s3_bucket.deploy_artifacts[0].arn : data.aws_s3_bucket.deploy_artifacts_existing[0].arn
  
}

########################################
# Deploy artifacts bucket
# Shared and owned by the primary environment
########################################

resource "aws_s3_bucket" "deploy_artifacts" {
  count = var.is_primary_environment ? 1 : 0

  bucket = "${var.project_name}-deploy-artifacts-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name        = "${var.project_name}-deploy-artifacts"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_public_access_block" "deploy_artifacts" {
  count = var.is_primary_environment ? 1 : 0

  bucket = aws_s3_bucket.deploy_artifacts[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "deploy_artifacts" {
  count = var.is_primary_environment ? 1 : 0

  bucket = aws_s3_bucket.deploy_artifacts[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

########################################
# Existing bucket used by non-primary
# environments
########################################

data "aws_s3_bucket" "deploy_artifacts_existing" {
  count = var.is_primary_environment ? 0 : 1

  bucket = "${var.project_name}-deploy-artifacts-${data.aws_caller_identity.current.account_id}"
}

########################################
# Shared bucket references
########################################

locals {
  deploy_artifacts_bucket = var.is_primary_environment ? aws_s3_bucket.deploy_artifacts[0].id : data.aws_s3_bucket.deploy_artifacts_existing[0].id

  deploy_artifacts_arn = var.is_primary_environment ? aws_s3_bucket.deploy_artifacts[0].arn : data.aws_s3_bucket.deploy_artifacts_existing[0].arn
}

*/

########################################
# Deploy artifacts bucket
# Shared and owned by the primary environment
########################################

resource "aws_s3_bucket" "deploy_artifacts" {
  count = var.is_primary_environment ? 1 : 0

  bucket = "${var.project_name}-deploy-artifacts-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name        = "${var.project_name}-deploy-artifacts"
    Environment = var.environment
  }
}

########################################
# Block public access
########################################

resource "aws_s3_bucket_public_access_block" "deploy_artifacts" {
  count = var.is_primary_environment ? 1 : 0

  bucket = aws_s3_bucket.deploy_artifacts[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

########################################
# Enable versioning
########################################

resource "aws_s3_bucket_versioning" "deploy_artifacts" {
  count = var.is_primary_environment ? 1 : 0

  bucket = aws_s3_bucket.deploy_artifacts[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

########################################
# Existing bucket for non-primary
# environments
########################################

data "aws_s3_bucket" "deploy_artifacts_existing" {
  count = var.is_primary_environment ? 0 : 1

  bucket = "${var.project_name}-deploy-artifacts-${data.aws_caller_identity.current.account_id}"
}

########################################
# Shared bucket references
########################################

locals {
  deploy_artifacts_bucket = var.is_primary_environment ? aws_s3_bucket.deploy_artifacts[0].id : data.aws_s3_bucket.deploy_artifacts_existing[0].id

  deploy_artifacts_arn = var.is_primary_environment ? aws_s3_bucket.deploy_artifacts[0].arn : data.aws_s3_bucket.deploy_artifacts_existing[0].arn
}

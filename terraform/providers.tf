

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # ---------------------------------------------------
  # Remote state management (recommended for teams)
  # 1. Create the S3 bucket + DynamoDB table ONCE, manually
  #    or via a small bootstrap config, before using this backend.
  # 2. Uncomment the block below and fill in your own values.
  # 3. Run: terraform init  (Terraform will migrate local state to S3)
  # ---------------------------------------------------
  backend "s3" {
    bucket       = "demo-project-state-bucket-k"
    key          = "terraform.tfstate"
    region       = "ap-south-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

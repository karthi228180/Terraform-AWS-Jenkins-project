########################################
# General
########################################

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Name prefix used for tagging and naming all resources"
  type        = string
  default     = "demo-proj"
}

variable "environment" {
  description = "Deployment environment (e.g. dev, staging, prod)"
  type        = string
  default     = "dev"
}

########################################
# Networking
########################################

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of AZs to spread subnets across"
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "admin_ssh_cidr" {
  description = "CIDR block allowed to SSH into EC2 instances "
  type        = string
  default     = "0.0.0.0/0"
}

########################################
# EC2 / Application
########################################

variable "instance_type" {
  description = "EC2 instance type for application servers"
  type        = string
  default     = "t2.large"
}

variable "instance_count" {
  description = "Number of EC2 application instances to launch"
  type        = number
  default     = 2
}

variable "key_name" {
  description = "Name of an existing EC2 key pair for SSH access"
  type        = string
  default     = "karthikeypair"
}

variable "ami_id" {
  description = "AMI ID to use for EC2 instances."
  type        = string
  default     = ""
}

########################################
# RDS PostgreSQL
########################################

variable "db_name" {
  description = "Initial PostgreSQL database name"
  type        = string
  default     = "Demoapp"
}

variable "db_username" {
  description = "Master username for RDS PostgreSQL"
  type        = string
  default     = "dbadmin"
}

variable "db_password" {
  description = "Master password for RDS PostgreSQL (set via TF_VAR_db_password or terraform.tfvars, never commit it)"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage for RDS in GB"
  type        = number
  default     = 20
}

variable "db_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "17"
}

variable "db_multi_az" {
  description = "Whether to deploy RDS in Multi-AZ for high availability"
  type        = bool
  default     = false
}

########################################
# Docker images (built & pushed by Jenkins)
########################################

variable "is_primary_environment" {
  description = <<-DESC
    Set true in exactly ONE environment (typically staging, applied first).
    That environment owns the shared CI/CD resources: the ECR repos, the
    Jenkins host, and the S3 bucket Jenkins uses to publish the deploy
    script. Every other environment (e.g. production) leaves this false and
    just references those shared resources instead of recreating them.
  DESC
  type        = bool
  default     = false
}

variable "app_image_tag" {
  description = "Tag of the app-tier image to run (Jenkins passes this in via -var on deploy)"
  type        = string
  default     = "latest"
}

variable "web_image_tag" {
  description = "Tag of the web-tier image to run (Jenkins passes this in via -var on deploy)"
  type        = string
  default     = "latest"
}

########################################
# Jenkins
########################################

variable "jenkins_instance_type" {
  description = "EC2 instance type for the Jenkins controller"
  type        = string
  default     = "t2.large"
}

variable "jenkins_admin_cidr" {
  description = "CIDR allowed to reach the Jenkins UI (8080) and SSH (22). Lock this down to your IP/VPN."
  type        = string
  default     = "0.0.0.0/0"
}

########################################
# Monitoring / alerting
########################################

variable "alert_email" {
  description = "Email address to receive CloudWatch alarm notifications (subscribes to the SNS topic)"
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "How long to keep CloudWatch Logs"
  type        = number
  default     = 30
}

# Copy this file to terraform.tfvars and fill in your own values.
# Never commit terraform.tfvars (it may contain secrets) - it's already in .gitignore.

aws_region   = "ap-south-1"
project_name = "demo-proj"
environment  = "staging"

availability_zones   = ["ap-south-1a", "ap-south-1b"]
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
admin_ssh_cidr       = "203.0.113.10/32" # <-- replace with YOUR IP, not 0.0.0.0/0

instance_type          = "t2.large"
instance_count         = 2
key_name               = "karthikeypair"
is_primary_environment = true

db_name     = "appdb"
db_username = "dbadmin"
# db_password is a secret - do NOT put it here.
# Instead export it as an environment variable before running terraform:
#   export TF_VAR_db_password="your-strong-password"
db_instance_class = "db.t3.micro"
db_multi_az       = false

# ---- Docker images ----
# Jenkins overrides these at deploy time with -var; the defaults here are
# only used for the very first `terraform apply` before any image exists.
app_image_tag = "latest"
web_image_tag = "latest"

# ---- Shared CI/CD resources ----
#is_primary_environment = true # staging owns the shared ECR repos, Jenkins host, and deploy bucket

# ---- Jenkins ----
jenkins_instance_type = "t3.medium"
jenkins_admin_cidr    = "203.0.113.10/32" # <-- replace with YOUR IP

# ---- Monitoring ----
alert_email        = "karthikcl248@gmail.com" # subscribes to CloudWatch alarm emails
log_retention_days = 30




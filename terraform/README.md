# AWS Infra with Terraform

Terraform project: VPC (public + private subnets), EC2 app servers running
the app-tier/web-tier containers, an Application Load Balancer, an RDS
PostgreSQL database, a Jenkins CI/CD host, ECR image repos, and CloudWatch
monitoring/logging/dashboards.

See **`../RUNBOOK.md`** for the full step-by-step of what to run and in what order.

## File structure

| File                        | Purpose                                                          |
|------------------------------|-------------------------------------------------------------------|
| `providers.tf`               | Terraform + AWS provider setup, remote state backend             |
| `variables.tf`               | All configurable input parameters                                |
| `vpc.tf`                     | VPC, public/private subnets, IGW, NAT gateway, routing           |
| `security_groups.tf`         | Security groups for ALB, EC2, RDS, Jenkins                        |
| `ec2.tf`                     | Application EC2 instances (Docker, pulls images from ECR)         |
| `alb.tf`                     | Load balancer, target group, listener                             |
| `rds.tf`                     | RDS PostgreSQL + CloudWatch log export + Enhanced Monitoring      |
| `ecr.tf`                     | Shared ECR repos (app-tier/web-tier images)                       |
| `iam.tf`                     | Least-privilege roles for app instances and Jenkins                |
| `ssm_parameters.tf`          | DB credentials as SecureString SSM parameters                     |
| `jenkins.tf`                 | Jenkins CI/CD host (Docker-based)                                  |
| `deploy_artifacts.tf`        | Shared S3 bucket Jenkins uses to publish the deploy script         |
| `monitoring.tf`               | CloudWatch agent config, log groups, alarms, SNS, 2 dashboards     |
| `outputs.tf`                  | Key resource outputs (ALB DNS, RDS endpoint, dashboards, etc.)     |
| `terraform.tfvars.example`   | Single-environment quick start                                     |
| `staging.tfvars.example`     | Staging env — owns the shared ECR/Jenkins/S3 resources             |
| `production.tfvars.example`  | Production env — references the shared resources staging created  |

## Architecture

```
Internet
   │
   ▼
[ ALB ] ── public subnets (2 AZs)
   │
   ▼
[ EC2 app x N ] ── private subnets (2 AZs) ── NAT Gateway → Internet (outbound only)
   │                 Docker: app-tier + web-tier containers
   ▼
[ RDS PostgreSQL ] ── private subnets, only reachable from EC2 security group

[ Jenkins EC2 ] ── public subnet, admin-CIDR-restricted, builds & pushes to ECR,
                    deploys via SSM Run Command
```

- Public subnets hold only the ALB, the NAT Gateway, and the Jenkins host.
- Private subnets hold the EC2 app instances and RDS — neither has a public IP.
- Security groups are chained: Internet → ALB SG → EC2 SG → RDS SG.

## Prerequisites

- Terraform >= 1.5
- AWS credentials configured (`aws configure` or environment variables)
- An existing EC2 key pair if you want SSH access (`key_name` variable)

## Remote state (recommended before first `apply`)

1. Create an S3 bucket and a DynamoDB table (with a `LockID` primary key) once,
   manually or with a small bootstrap Terraform config.
2. Uncomment and fill in the `backend "s3" { ... }` block in `providers.tf`
   (give staging and production different `key` values in that block).
3. Run `terraform init` — Terraform will offer to migrate local state to S3.

If you skip this step, Terraform just uses local state (`terraform.tfstate`
in this folder) — fine for solo experimentation, not for teams or for
running two environments from the same machine (use separate directories
or workspaces if you stay on local state).

## Usage

See `../RUNBOOK.md` for the full walkthrough. Short version:

```bash
cp staging.tfvars.example staging.tfvars   # edit CIDRs, key_name, alert_email
export TF_VAR_db_password="ChangeMe123!"   # never put this in a file
terraform init
terraform plan  -var-file=staging.tfvars
terraform apply -var-file=staging.tfvars
terraform output jenkins_url
```

Then, once staging is up and Jenkins is configured:

```bash
cp production.tfvars.example production.tfvars   # is_primary_environment = false
export TF_VAR_db_password="AnotherStrongPassword!"
terraform apply -var-file=production.tfvars
```

## Cleanup

```bash
terraform destroy -var-file=production.tfvars   # destroy non-primary environments first
terraform destroy -var-file=staging.tfvars
```

## Notes / things to adjust for production

- `admin_ssh_cidr` / `jenkins_admin_cidr` default to `0.0.0.0/0` — set them to
  your own IP/VPN range before applying.
- `db_multi_az = true` for production database high availability (already set
  in `production.tfvars.example`).
- Consider adding HTTPS (ACM cert + 443 listener) on the ALB for production traffic.
- Consider an Auto Scaling Group instead of fixed `instance_count` EC2 instances
  if you need automatic scaling/self-healing.


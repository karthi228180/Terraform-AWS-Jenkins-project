# Runbook: how to actually run this project

This answers "where do I install Jenkins / Docker / the monitoring tools" directly:

| Tool | Where it runs | Installed by |
|---|---|---|
| **Docker** | On the Jenkins EC2 host (to build images) *and* on every app-tier EC2 instance (to run the containers) | Terraform `user_data` in `jenkins.tf` and `ec2.tf` — you don't install it by hand |
| **Jenkins** | One dedicated EC2 instance (`terraform/jenkins.tf`), running as a Docker container on that host | Terraform, on first boot |
| **Monitoring** | CloudWatch (AWS-managed — no server to install or maintain) | The CloudWatch agent (installed by `user_data`) ships metrics/logs; dashboards/alarms are created by `terraform/monitoring.tf` |

Nothing runs on your laptop except the `terraform` and `aws` CLIs you use to stand things up.

## Architecture at a glance

```
                     ┌────────────────────────────┐
                     │   Jenkins EC2 (public)      │  <- you SSH/browse here
                     │   Docker + Jenkins + Trivy   │
                     └───────────┬─────────────────┘
                                 │ push images (ECR) / SSM Run Command
                                 ▼
Internet ── ALB (public subnets) ── EC2 app x N (private, Docker: app-tier + web-tier)
                                          │
                                          ▼
                                  RDS PostgreSQL (private)

All metrics/logs -> CloudWatch (agent on each EC2 host + container awslogs driver)
```

- **staging** and **production** are two separate applies of the same Terraform code
  (different `-var-file`), each with its own VPC/ALB/EC2/RDS.
- **ECR repos, the Jenkins host, and the deploy-artifacts S3 bucket are shared** —
  only the "primary" environment (staging) creates them; production just references
  them. This is what `is_primary_environment` controls.
- Jenkins builds one image, pushes it to ECR once, and **the same image tag** gets
  deployed to staging, then (after approval) promoted to production — no rebuilding.

## First-time setup, step by step

### 1. Prerequisites
- An AWS account + credentials configured locally (`aws configure`)
- Terraform >= 1.5
- An EC2 key pair in your target region (for SSH access, optional but recommended)

### 2. Stand up staging (this also creates the shared ECR/Jenkins/S3 resources)

```bash
cd terraform
cp staging.tfvars.example staging.tfvars
# edit staging.tfvars: set admin_ssh_cidr / jenkins_admin_cidr to YOUR IP,
# key_name to your keypair, alert_email to where you want alarm emails

export TF_VAR_db_password="ChangeMe123!"   # never put this in a file
terraform init
terraform plan  -var-file=staging.tfvars
terraform apply -var-file=staging.tfvars
```

Grab the outputs you'll need next:
```bash
terraform output jenkins_url          # http://<ip>:8080
terraform output alb_dns_name         # staging app URL
terraform output dashboard_infra_app_url
terraform output dashboard_database_url
terraform output ecr_app_tier_repository_url
terraform output ecr_web_tier_repository_url
```

### 3. Finish Jenkins setup (one-time, in the browser)
1. Open `jenkins_url`. Get the initial admin password:
   ```bash
   ssh ec2-user@<jenkins_public_ip> "sudo docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword"
   ```
2. Install the suggested plugins, plus: **Docker Pipeline, Pipeline: Input Step,
   Credentials Binding, AnsiColor, JUnit**.
3. Add credentials (Manage Jenkins → Credentials):
   - `test-db-password` (Secret text) — any throwaway password, used only by the
     disposable integration-test Postgres container
   - `slack-webhook-url` (Secret text)
   - `notify-email` (Secret text)
   - No AWS keys — the Jenkins host already has an IAM role with exactly the
     ECR/SSM/S3 permissions the pipeline needs.
4. Create a **Multibranch Pipeline** job pointing at your git repo. This makes
   `when { branch 'main' }` in the `Jenkinsfile` correctly distinguish PRs from `main`.
5. Create a **`release-managers`** permission group/role and add whoever should be
   allowed to click "approve" on production deploys (used by the `input` step).

### 4. Push code and watch it run
- Open a PR → pipeline runs tests + dependency scan only.
- Merge to `main` → pipeline builds images, scans them, pushes to ECR, deploys to
  staging automatically, smoke-tests it, then **pauses for approval**.
- Approve in the Jenkins UI (or from the console: `Console Output` → `Proceed`) →
  the exact same image gets deployed to production.

### 5. Stand up production

```bash
cp production.tfvars.example production.tfvars
# edit: same admin CIDR conventions, db_multi_az = true, bigger instance_type if needed
export TF_VAR_db_password="AnotherStrongPassword!"
terraform apply -var-file=production.tfvars
```

`is_primary_environment = false` here means this apply reuses the ECR repos,
Jenkins host, and deploy bucket staging already created — it only creates
production's own VPC/ALB/EC2/RDS/dashboards/alarms.

## Monitoring — where to look

- **Dashboards**: CloudWatch console → Dashboards → `myapp-staging-infra-and-app`
  and `myapp-staging-database` (and the `-production-` equivalents). Direct links
  are in `terraform output dashboard_infra_app_url` / `dashboard_database_url`.
- **Alarms**: CloudWatch → Alarms. All of them publish to the SNS topic
  (`terraform output sns_alerts_topic_arn`), which emails `alert_email` and
  also receives Jenkins pipeline-failure notifications.
- **Logs**: CloudWatch Logs → log groups named `/myapp/<env>/application`,
  `/myapp/<env>/access`, `/myapp/<env>/system`. ALB's own access logs land as
  files in the `myapp-<env>-alb-logs-<account>` S3 bucket. RDS Postgres logs
  appear under `/aws/rds/instance/<db-id>/postgresql`.

## Day-to-day operations

- **Redeploy without a code change** (e.g. roll back a bad tag):
  ```bash
  ./scripts/ci-deploy.sh staging    <account>.dkr.ecr.<region>.amazonaws.com/myapp-app-tier:<tag> \
                                     <account>.dkr.ecr.<region>.amazonaws.com/myapp-web-tier:<tag>
  ```
  (Run this from the Jenkins host, or anywhere with the same IAM permissions.)
- **SSH to an app instance** (they're in private subnets — use SSM instead of
  opening SSH to them):
  ```bash
  aws ssm start-session --target <instance-id>
  ```
- **Tear down**: `terraform destroy -var-file=production.tfvars` then
  `... staging.tfvars` (destroy the non-primary environment first, since it
  only references the shared ECR/Jenkins/S3 resources rather than owning them).

## Cost note
This provisions real billable AWS resources (2+ EC2 instances per environment,
a NAT Gateway per environment, an RDS instance per environment, a Jenkins host,
ALB, CloudWatch). Destroy environments you're not using.

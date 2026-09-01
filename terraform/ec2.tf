########################################
# Latest Amazon Linux 2023 AMI (used only if var.ami_id is left empty)
########################################
/*
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.amazon_linux.id

  app_user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail

    # ---- Docker ----
    dnf install -y docker
    systemctl enable docker
    systemctl start docker
    usermod -aG docker ec2-user

    # ---- CloudWatch agent (host CPU/mem/disk metrics + system logs) ----
    dnf install -y amazon-cloudwatch-agent

    cat <<'CWCONFIG' > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
    ${local.cw_agent_config_app}
    CWCONFIG

    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
      -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

    # ---- Pull application images from ECR ----
    aws ecr get-login-password --region ${var.aws_region} | \
      docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com

    docker pull ${local.app_tier_repo_url}:${var.app_image_tag}
    docker pull ${local.web_tier_repo_url}:${var.web_image_tag}

    # ---- DB credentials come from SSM Parameter Store, never from user_data in plaintext ----
    DB_HOST=$(aws ssm get-parameter --name "${aws_ssm_parameter.db_host.name}" --region ${var.aws_region} --query Parameter.Value --output text)
    DB_NAME=$(aws ssm get-parameter --name "${aws_ssm_parameter.db_name.name}" --region ${var.aws_region} --query Parameter.Value --output text)
    DB_USER=$(aws ssm get-parameter --name "${aws_ssm_parameter.db_username.name}" --with-decryption --region ${var.aws_region} --query Parameter.Value --output text)
    DB_PWD=$(aws ssm get-parameter --name "${aws_ssm_parameter.db_password.name}" --with-decryption --region ${var.aws_region} --query Parameter.Value --output text)

    docker network create appnet || true

    docker run -d --name app-tier --network appnet --restart unless-stopped \
      -e DB_HOST="$DB_HOST" -e DB_PORT=5432 -e DB_DATABASE="$DB_NAME" \
      -e DB_USER="$DB_USER" -e DB_PWD="$DB_PWD" -e DB_SSL=true \
      --log-driver=awslogs --log-opt awslogs-region=${var.aws_region} \
      --log-opt awslogs-group=${aws_cloudwatch_log_group.app_application.name} \
      --log-opt awslogs-stream=$(hostname)-app-tier \
      ${local.app_tier_repo_url}:${var.app_image_tag}

    docker run -d --name web-tier --network appnet --restart unless-stopped \
      -p 80:8080 \
      --log-driver=awslogs --log-opt awslogs-region=${var.aws_region} \
      --log-opt awslogs-group=${aws_cloudwatch_log_group.app_access.name} \
      --log-opt awslogs-stream=$(hostname)-web-tier \
      ${local.web_tier_repo_url}:${var.web_image_tag}
  EOF
}

########################################
# EC2 Application Instances (deployed in private subnets)
########################################

resource "aws_instance" "app" {
  count                  = var.instance_count
  ami                    = local.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private[count.index % length(aws_subnet.private)].id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  key_name                = var.key_name != "" ? var.key_name : null
  iam_instance_profile    = aws_iam_instance_profile.app_ec2.name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    encrypted              = true
  }

  # Deploys re-run this via SSM Run Command instead of replacing the instance
  # (see PIPELINE.md / deploy.sh) -- user_data only handles first boot.
  user_data = local.app_user_data

  tags = {
    Name          = "${var.project_name}-app-${count.index + 1}"
    Environment   = var.environment
    Role          = "app-tier"
    # Read by scripts/deploy.sh (via SSM) so redeploys can find the right
    # SSM parameters / log groups without needing a fresh terraform apply.
    SsmParamPath  = "/${var.project_name}/${var.environment}"
  }
}
  */



data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

locals {
  ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu.id

  app_user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail

    # ---- Update system ----
    apt-get update -y
    apt-get upgrade -y

    # ---- Install required packages ----
    apt-get install -y \
      docker.io \
      unzip \
      curl \
      wget \
      ca-certificates

    # ---- Docker ----
    systemctl enable docker
    systemctl start docker

    # Ubuntu default user is "ubuntu"
    usermod -aG docker ubuntu

    # ---- AWS CLI ----
    if ! command -v aws >/dev/null 2>&1; then
      curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
        -o "/tmp/awscliv2.zip"

      unzip -q /tmp/awscliv2.zip -d /tmp

      /tmp/aws/install

      rm -rf /tmp/aws /tmp/awscliv2.zip
    fi

    # ---- CloudWatch Agent ----
    wget -q \
      https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb \
      -O /tmp/amazon-cloudwatch-agent.deb

    dpkg -i -E /tmp/amazon-cloudwatch-agent.deb || true

    apt-get install -f -y

    cat <<'CWCONFIG' > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
    ${local.cw_agent_config_app}
    CWCONFIG

    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
      -a fetch-config \
      -m ec2 \
      -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
      -s

    # ---- Pull application images from ECR ----
    aws ecr get-login-password \
      --region ${var.aws_region} | \
      docker login \
      --username AWS \
      --password-stdin \
      ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com

    docker pull ${local.app_tier_repo_url}:${var.app_image_tag}
    docker pull ${local.web_tier_repo_url}:${var.web_image_tag}

    # ---- DB credentials come from SSM Parameter Store ----
    # Never store DB credentials directly in user_data

    DB_HOST=$(aws ssm get-parameter \
      --name "${aws_ssm_parameter.db_host.name}" \
      --region ${var.aws_region} \
      --query Parameter.Value \
      --output text)

    DB_NAME=$(aws ssm get-parameter \
      --name "${aws_ssm_parameter.db_name.name}" \
      --region ${var.aws_region} \
      --query Parameter.Value \
      --output text)

    DB_USER=$(aws ssm get-parameter \
      --name "${aws_ssm_parameter.db_username.name}" \
      --with-decryption \
      --region ${var.aws_region} \
      --query Parameter.Value \
      --output text)

    DB_PWD=$(aws ssm get-parameter \
      --name "${aws_ssm_parameter.db_password.name}" \
      --with-decryption \
      --region ${var.aws_region} \
      --query Parameter.Value \
      --output text)

    # ---- Docker network ----
    docker network create appnet || true

    # ---- Application tier ----
    docker run -d \
      --name app-tier \
      --network appnet \
      --restart unless-stopped \
      -e DB_HOST="$DB_HOST" \
      -e DB_PORT=5432 \
      -e DB_DATABASE="$DB_NAME" \
      -e DB_USER="$DB_USER" \
      -e DB_PWD="$DB_PWD" \
      -e DB_SSL=true \
      --log-driver=awslogs \
      --log-opt awslogs-region=${var.aws_region} \
      --log-opt awslogs-group=${aws_cloudwatch_log_group.app_application.name} \
      --log-opt awslogs-stream=$(hostname)-app-tier \
      ${local.app_tier_repo_url}:${var.app_image_tag}

    # ---- Web tier ----
    docker run -d \
      --name web-tier \
      --network appnet \
      --restart unless-stopped \
      -p 80:8080 \
      --log-driver=awslogs \
      --log-opt awslogs-region=${var.aws_region} \
      --log-opt awslogs-group=${aws_cloudwatch_log_group.app_access.name} \
      --log-opt awslogs-stream=$(hostname)-web-tier \
      ${local.web_tier_repo_url}:${var.web_image_tag}
  EOF
}


resource "aws_instance" "app" {
  count                  = var.instance_count
  ami                    = local.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private[count.index % length(aws_subnet.private)].id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  #key_name               = var.key_name != "" ? var.key_name : null #
  key_name               = "karthikeypair"
  iam_instance_profile   = aws_iam_instance_profile.app_ec2.name

  root_block_device {
    volume_type = "gp3"
    volume_size = 35
    encrypted   = true
  }

  # user_data runs only during first boot.
  # Redeployments can be handled through SSM Run Command.

  user_data = local.app_user_data

  tags = {
    Name         = "${var.project_name}-app-${count.index + 1}"
    Environment  = var.environment
    Role         = "app-tier"
    SsmParamPath = "/${var.project_name}/${var.environment}"
  }
}


########################################
# Jenkins host
#   - Lives in a public subnet because it needs outbound internet for
#     plugin/base-image downloads and to reach ECR/GitHub; inbound is
#     locked to jenkins_admin_cidr only (see security_groups.tf).
#   - Runs Jenkins itself as a Docker container for easy upgrades/backups.
#   - Has its own Docker engine to build the app-tier/web-tier images.
########################################
/*
resource "aws_instance" "jenkins" {
  count                       = var.is_primary_environment ? 1 : 0
  ami                         = local.ami_id
  instance_type               = var.jenkins_instance_type
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.jenkins[0].id]
  #key_name                    = var.key_name != "" ? var.key_name : null #
  key_name                    = "karthikeypair"
  iam_instance_profile        = aws_iam_instance_profile.jenkins[0].name
  associate_public_ip_address = true

  root_block_device {
    volume_type = "gp3"
    volume_size = 40 # Jenkins home + Docker image cache needs more room than the app hosts
    encrypted   = true
  }

  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail

    dnf install -y docker
    systemctl enable docker
    systemctl start docker
    usermod -aG docker ec2-user

    dnf install -y amazon-cloudwatch-agent
    cat <<'CWCONFIG' > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
    ${local.cw_agent_config_app}
    CWCONFIG
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
      -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

    mkdir -p /var/jenkins_home
    chown 1000:1000 /var/jenkins_home

    # Jenkins itself, with access to the host's Docker socket so pipeline
    # stages can run `docker build` / `docker push` directly.
    docker run -d --name jenkins --restart unless-stopped \
      -p 8080:8080 -p 50000:50000 \
      -v /var/jenkins_home:/var/jenkins_home \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -e JAVA_OPTS="-Djenkins.install.runSetupWizard=true" \
      jenkins/jenkins:lts

    # The Jenkins container needs the `docker` CLI available inside it to
    # use the mounted socket; install it once the container is up.
    sleep 15
    docker exec -u root jenkins bash -c "apt-get update && apt-get install -y docker.io curl unzip"

    # AWS CLI + Trivy + Terraform on the host so pipeline stages (running via
    # the mounted socket / host exec) can use them.
    dnf install -y unzip dnf-plugins-core
    curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
    unzip -q /tmp/awscliv2.zip -d /tmp && /tmp/aws/install
    curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin
    dnf config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
    dnf install -y terraform
  EOF

  tags = {
    Name = "${var.project_name}-jenkins"
    Role = "ci-cd"
  }
}   */

##################################################################################################
/*
########################################
# Jenkins host
#   - Lives in a public subnet because it needs outbound internet for
#     plugin/base-image downloads and to reach ECR/GitHub; inbound is
#     locked to jenkins_admin_cidr only (see security_groups.tf).
#   - Runs Jenkins itself as a Docker container for easy upgrades/backups.
#   - Has its own Docker engine to build the app-tier/web-tier images.
########################################

resource "aws_instance" "jenkins" {
  count                       = var.is_primary_environment ? 1 : 0
  ami                         = local.ami_id
  instance_type               = var.jenkins_instance_type
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.jenkins[0].id]
  key_name                    = "karthikeypair"
  iam_instance_profile        = aws_iam_instance_profile.jenkins[0].name
  associate_public_ip_address = true

  root_block_device {
    volume_type = "gp3"
    volume_size = 40 # Jenkins home + Docker image cache needs more room than the app hosts
    encrypted   = true
  }

  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail

    # ---------- Install Docker ----------
    dnf update -y
    dnf install -y docker

    systemctl enable docker
    systemctl start docker

    # Wait until Docker is ready
    for i in {1..30}; do
      if docker info >/dev/null 2>&1; then
        break
      fi
      sleep 2
    done

    usermod -aG docker ec2-user

    # ---------- Install Docker Compose v2 ----------
    mkdir -p /usr/local/lib/docker/cli-plugins
    curl -sfL https://github.com/docker/compose/releases/download/v2.30.0/docker-compose-linux-x86_64 \
      -o /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
    ln -sf /usr/local/lib/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose

    # Verify docker compose works
    docker compose version || docker-compose version

    # ---------- Install CloudWatch Agent ----------
    dnf install -y amazon-cloudwatch-agent
    cat <<'CWCONFIG' > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
    ${local.cw_agent_config_app}
    CWCONFIG

    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
      -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

    # ---------- Prepare Jenkins home ----------
    mkdir -p /var/jenkins_home
    chown 1000:1000 /var/jenkins_home

    # ---------- Run Jenkins in Docker ----------
    docker run -d --name jenkins --restart unless-stopped \
      -p 8080:8080 -p 50000:50000 \
      -v /var/jenkins_home:/var/jenkins_home \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -e JAVA_OPTS="-Djenkins.install.runSetupWizard=true" \
      jenkins/jenkins:lts

    # Wait for Jenkins container to be up
    for i in {1..30}; do
      if docker ps --format '{{.Names}}' | grep -q '^jenkins$'; then
        break
      fi
      sleep 2
    done

    # ---------- Install tools inside Jenkins container ----------
    # Install docker CLI + common tools inside Jenkins so pipelines can use them
    docker exec -u root jenkins bash -c '
      set -euxo pipefail
      apt-get update
      apt-get install -y docker.io curl unzip git
    '

    # ---------- Install tools on the host (for pipelines / admin) ----------
    dnf install -y unzip dnf-plugins-core

    # AWS CLI v2
    curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
    unzip -q /tmp/awscliv2.zip -d /tmp
    /tmp/aws/install

    # Trivy
    curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin

    # Terraform
    dnf config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
    dnf install -y terraform
  EOF

  tags = {
    Name = "${var.project_name}-jenkins"
    Role = "ci-cd"
  }
}   */
#####################################################################################################

########################################
# Jenkins host
#   - Lives in a public subnet because it needs outbound internet for
#     plugin/base-image downloads and to reach ECR/GitHub; inbound is
#     locked to jenkins_admin_cidr only (see security_groups.tf).
#   - Runs Jenkins itself as a Docker container for easy upgrades/backups.
#   - Has its own Docker engine to build the app-tier/web-tier images.
########################################

resource "aws_instance" "jenkins" {
  count                       = var.is_primary_environment ? 1 : 0
  ami                         = local.ami_id
  instance_type               = var.jenkins_instance_type
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.jenkins[0].id]
  key_name                    = "karthikeypair"
  iam_instance_profile        = aws_iam_instance_profile.jenkins[0].name
  associate_public_ip_address = true

  root_block_device {
    volume_type = "gp3"
    volume_size = 40 # Jenkins home + Docker image cache needs more room than the app hosts
    encrypted   = true
  }

  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail

    # ---------- Update and install basic tools ----------
    apt-get update
    apt-get install -y \
      apt-transport-https \
      ca-certificates \
      curl \
      gnupg \
      lsb-release \
      unzip \
      git

    # ---------- Install Docker ----------
    # Use Docker's official repo for Ubuntu
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    systemctl enable docker
    systemctl start docker

    # Wait until Docker is ready
    for i in {1..30}; do
      if docker info >/dev/null 2>&1; then
        break
      fi
      sleep 2
    done

    usermod -aG docker ubuntu

    # ---------- Install Docker Compose v2 (standalone, in case plugin is missing) ----------
    mkdir -p /usr/local/lib/docker/cli-plugins
    curl -sfL https://github.com/docker/compose/releases/download/v2.30.0/docker-compose-linux-x86_64 \
      -o /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
    ln -sf /usr/local/lib/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose

    # Verify docker compose works
    docker compose version || docker-compose version

    # ---------- Install CloudWatch Agent (Ubuntu package) ----------
    curl -fsSL https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb -o /tmp/amazon-cloudwatch-agent.deb
    dpkg -i /tmp/amazon-cloudwatch-agent.deb || apt-get install -f -y

    cat <<'CWCONFIG' > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
    ${local.cw_agent_config_app}
    CWCONFIG

    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
      -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

    # ---------- Prepare Jenkins home ----------
    mkdir -p /var/jenkins_home
    chown 1000:1000 /var/jenkins_home

    # ---------- Run Jenkins in Docker ----------
    docker run -d --name jenkins --restart unless-stopped \
      -p 8080:8080 -p 50000:50000 \
      -v /var/jenkins_home:/var/jenkins_home \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -e JAVA_OPTS="-Djenkins.install.runSetupWizard=true" \
      jenkins/jenkins:lts

    # Wait for Jenkins container to be up
    for i in {1..30}; do
      if docker ps --format '{{.Names}}' | grep -q '^jenkins$'; then
        break
      fi
      sleep 2
    done

    # ---------- Install tools inside Jenkins container ----------
    # Install docker CLI + common tools inside Jenkins so pipelines can use them
    docker exec -u root jenkins bash -c '
      set -euxo pipefail
      apt-get update
      apt-get install -y docker.io curl unzip git
    '

    # ---------- Install tools on the host (for pipelines / admin) ----------
    # AWS CLI v2
    curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
    unzip -q /tmp/awscliv2.zip -d /tmp
    sudo /tmp/aws/install

    # Trivy
    curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin

    # Terraform (via HashiCorp apt repo)
    apt-get install -y gnupg software-properties-common
    curl -fsSL https://rpm.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://rpm.releases.hashicorp.com/ubuntu $(lsb_release -cs) main" \
      | tee /etc/apt/sources.list.d/hashicorp.list
    apt-get update
    apt-get install -y terraform
  EOF

  tags = {
    Name = "${var.project_name}-jenkins"
    Role = "ci-cd"
  }
}
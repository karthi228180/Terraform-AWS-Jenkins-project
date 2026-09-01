#!/bin/bash
# Runs ON each app EC2 instance via SSM Run Command (triggered by Jenkins).
# Args: $1 = full app-tier image URI (with tag)   $2 = full web-tier image URI (with tag)
set -euxo pipefail

APP_IMAGE="$1"
WEB_IMAGE="$2"
REGION="$(curl -s http://169.254.169.254/latest/meta-data/placement/region)"
REGISTRY="$(echo "$APP_IMAGE" | cut -d/ -f1)"
INSTANCE_ID="$(curl -s http://169.254.169.254/latest/meta-data/instance-id)"

aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"

docker pull "$APP_IMAGE"
docker pull "$WEB_IMAGE"

# SsmParamPath tag (set by Terraform) tells this script which SSM path and
# CloudWatch log groups belong to this environment, so it works unmodified
# across staging and production.
PARAM_PATH=$(aws ec2 describe-tags --region "$REGION" \
  --filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=SsmParamPath" \
  --query 'Tags[0].Value' --output text)
PROJECT=$(echo "$PARAM_PATH" | cut -d/ -f2)
ENVIRONMENT=$(echo "$PARAM_PATH" | cut -d/ -f3)
APP_LOG_GROUP="/${PROJECT}/${ENVIRONMENT}/application"
ACCESS_LOG_GROUP="/${PROJECT}/${ENVIRONMENT}/access"

DB_HOST=$(aws ssm get-parameter --name "${PARAM_PATH}/db/host" --region "$REGION" --query Parameter.Value --output text)
DB_NAME=$(aws ssm get-parameter --name "${PARAM_PATH}/db/name" --region "$REGION" --query Parameter.Value --output text)
DB_USER=$(aws ssm get-parameter --name "${PARAM_PATH}/db/username" --with-decryption --region "$REGION" --query Parameter.Value --output text)
DB_PWD=$(aws ssm get-parameter --name "${PARAM_PATH}/db/password" --with-decryption --region "$REGION" --query Parameter.Value --output text)

deploy_container() {
  local name="$1" image="$2" port_map="$3" log_group="$4" health_port="$5"; shift 5
  local new="${name}-new"

  docker rm -f "$new" 2>/dev/null || true

  # shellcheck disable=SC2086
  docker run -d --name "$new" --network appnet --restart unless-stopped $port_map \
    --log-driver=awslogs --log-opt awslogs-region="$REGION" \
    --log-opt awslogs-group="$log_group" \
    --log-opt awslogs-stream="${name}-$(date +%s)" \
    "$@" "$image"

  sleep 5
  # Fail fast and leave the OLD container running if the new one is unhealthy.
  docker exec "$new" wget -qO- "http://localhost:${health_port}/health"

  docker rm -f "$name" 2>/dev/null || true
  docker rename "$new" "$name"
}

deploy_container app-tier "$APP_IMAGE" "" "$APP_LOG_GROUP" 4000 \
  -e DB_HOST="$DB_HOST" -e DB_PORT=5432 -e DB_DATABASE="$DB_NAME" \
  -e DB_USER="$DB_USER" -e DB_PWD="$DB_PWD" -e DB_SSL=true

deploy_container web-tier "$WEB_IMAGE" "-p 80:8080" "$ACCESS_LOG_GROUP" 8080

echo "Deploy finished on $INSTANCE_ID: app=$APP_IMAGE web=$WEB_IMAGE"

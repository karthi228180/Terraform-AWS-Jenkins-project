#!/bin/bash
# Run FROM Jenkins. Publishes scripts/deploy.sh to the shared S3 bucket
# under this environment's prefix, then triggers it on every app-tier EC2
# instance in that environment via SSM Run Command and waits for the result.
#
# Usage: ./scripts/ci-deploy.sh <staging|production> <app-image:tag> <web-image:tag>
set -euo pipefail

ENVIRONMENT="$1"
APP_IMAGE="$2"
WEB_IMAGE="$3"
REGION="${AWS_REGION:-us-east-1}"
PROJECT="${PROJECT_NAME:-myapp}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="${PROJECT}-deploy-artifacts-${ACCOUNT_ID}"

echo "==> Publishing deploy.sh to s3://${BUCKET}/${ENVIRONMENT}/deploy.sh"
aws s3 cp "$(dirname "$0")/deploy.sh" "s3://${BUCKET}/${ENVIRONMENT}/deploy.sh" --region "$REGION"

echo "==> Finding app-tier instances tagged Environment=${ENVIRONMENT}"
INSTANCE_IDS=$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:Environment,Values=${ENVIRONMENT}" "Name=tag:Role,Values=app-tier" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' --output text)

if [ -z "$INSTANCE_IDS" ]; then
  echo "No running instances found for Environment=${ENVIRONMENT} -- did you run 'terraform apply' for it?"
  exit 1
fi

echo "==> Deploying $APP_IMAGE / $WEB_IMAGE to: $INSTANCE_IDS"
COMMAND_ID=$(aws ssm send-command --region "$REGION" \
  --document-name "AWS-RunShellScript" \
  --targets "Key=InstanceIds,Values=$(echo $INSTANCE_IDS | tr ' ' ',')" \
  --parameters commands="[
    \"aws s3 cp s3://${BUCKET}/${ENVIRONMENT}/deploy.sh /tmp/deploy.sh --region ${REGION}\",
    \"chmod +x /tmp/deploy.sh\",
    \"/tmp/deploy.sh ${APP_IMAGE} ${WEB_IMAGE}\"
  ]" \
  --comment "Jenkins deploy ${ENVIRONMENT} build ${BUILD_NUMBER:-manual}" \
  --query 'Command.CommandId' --output text)

echo "==> SSM command: $COMMAND_ID -- waiting for completion..."
for id in $INSTANCE_IDS; do
  aws ssm wait command-executed --region "$REGION" --command-id "$COMMAND_ID" --instance-id "$id" || {
    echo "Deploy FAILED on $id:"
    aws ssm get-command-invocation --region "$REGION" --command-id "$COMMAND_ID" --instance-id "$id" \
      --query 'StandardErrorContent' --output text
    exit 1
  }
  echo "  $id: OK"
done

echo "==> Deploy to ${ENVIRONMENT} complete."

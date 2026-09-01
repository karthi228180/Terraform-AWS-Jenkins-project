/*
 * CI/CD pipeline for the aws-three-tier-web-architecture-workshop app,
 * running on the Jenkins host that terraform/jenkins.tf provisions.
 *
 * Flow:
 *   Pull Request   -> checkout, install, unit + integration tests, dependency scan
 *   Merge to main  -> tests + scans again, build & push images to ECR, deploy to staging
 *   After staging  -> manual approval gate
 *   On approval    -> deploy the SAME image tag to production
 *
 * Infra assumption: application-code/{app-tier,web-tier} are built into
 * Docker images, pushed to ECR, and rolled out to the EC2 app instances via
 * `aws ssm send-command` running scripts/deploy.sh (no Kubernetes here --
 * this pipeline targets the plain EC2 + ALB + RDS stack in terraform/).
 *
 * Required Jenkins credentials (Manage Jenkins > Credentials):
 *   - "test-db-password"     Secret text -> throwaway password for the CI-only Postgres container
 *   - "slack-webhook-url"    Secret text -> Slack incoming webhook URL
 *   - "notify-email"         Secret text -> distribution list / email address
 *   (No AWS keys needed -- the Jenkins EC2 host has an IAM instance role
 *    with exactly the ECR/SSM/S3 permissions it needs; see terraform/iam.tf)
 *
 * Required Jenkins plugins: Docker Pipeline, Pipeline: Input Step,
 * Credentials Binding, JUnit, AnsiColor.
 *
 * Required tools on the Jenkins host (already installed by jenkins.tf's
 * user_data): docker, aws-cli v2, trivy, node/npm.
 */

pipeline {
    agent any

    options {
        timestamps()
        timeout(time: 45, unit: 'MINUTES')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '30'))
        ansiColor('xterm')
    }

    environment {
        AWS_REGION       = 'ap-south-1'
        PROJECT_NAME     = 'demo-proj'
        ACCOUNT_ID       = sh(script: 'aws sts get-caller-identity --query Account --output text', returnStdout: true).trim()
        REGISTRY         = "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        IMAGE_APP_TIER   = "${REGISTRY}/${PROJECT_NAME}-app-tier"
        IMAGE_WEB_TIER   = "${REGISTRY}/${PROJECT_NAME}-web-tier"
        DEPLOY_BUCKET    = "${PROJECT_NAME}-deploy-artifacts-${ACCOUNT_ID}"
        IMAGE_TAG        = "${env.GIT_COMMIT ? env.GIT_COMMIT.take(8) : env.BUILD_NUMBER}"
        TEST_DB_PWD      = credentials('test-db-password') // dummy/local password, not prod creds
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Install dependencies') {
            parallel {
                stage('app-tier') {
                    steps { dir('application-code/app-tier') { sh 'npm ci' } }
                }
                stage('web-tier') {
                    steps { dir('application-code/web-tier') { sh 'npm ci' } }
                }
            }
        }

        // ---- Runs on every PR, and again on main as a safety net ----
        stage('Unit tests') {
            steps {
                dir('application-code/app-tier') {
                    sh 'npm run test:unit -- --ci --reporters=default --reporters=jest-junit'
                }
                dir('application-code/web-tier') {
                    sh 'CI=true npm test -- --watchAll=false'
                }
            }
            post {
                always { junit allowEmptyResults: true, testResults: 'application-code/**/junit.xml' }
            }
        }

        stage('Integration tests') {
            steps {
                sh '''
                    docker run -d --rm --name ci-postgres-$BUILD_NUMBER \
                        -e POSTGRES_PASSWORD=$TEST_DB_PWD \
                        -e POSTGRES_DB=webappdb_test \
                        -p 5433:5432 postgres:16-alpine
                    for i in $(seq 1 20); do
                        docker exec ci-postgres-$BUILD_NUMBER pg_isready -U postgres && break
                        sleep 2
                    done
                    docker exec -i ci-postgres-$BUILD_NUMBER psql -U postgres -d webappdb_test \
                        < application-code/app-tier/schema.postgresql.sql
                '''
                dir('application-code/app-tier') {
                    withEnv([
                        'DB_HOST=localhost', 'DB_PORT=5433', 'DB_DATABASE=webappdb_test',
                        'DB_USER=postgres', "DB_PWD=${TEST_DB_PWD}", 'DB_SSL=false'
                    ]) {
                        sh 'npm run test:integration'
                    }
                }
            }
            post {
                always { sh 'docker stop ci-postgres-$BUILD_NUMBER || true' }
            }
        }

        // ---- Dependency vulnerability scan (SCA), on every PR too ----
        stage('Dependency vulnerability scan') {
            steps {
                dir('application-code/app-tier') {
                    sh 'npm audit --audit-level=high || true'
                    sh 'trivy fs --exit-code 1 --severity CRITICAL,HIGH --ignore-unfixed .'
                }
                dir('application-code/web-tier') {
                    sh 'npm audit --audit-level=high || true'
                    sh 'trivy fs --exit-code 1 --severity CRITICAL,HIGH --ignore-unfixed .'
                }
            }
        }

        // ---- Everything past this point only runs on main after merge ----
        stage('Build Docker images') {
            when { branch 'main' }
            steps {
                dir('application-code/app-tier') {
                    sh "docker build -t ${IMAGE_APP_TIER}:${IMAGE_TAG} -t ${IMAGE_APP_TIER}:latest ."
                }
                dir('application-code/web-tier') {
                    sh "docker build -t ${IMAGE_WEB_TIER}:${IMAGE_TAG} -t ${IMAGE_WEB_TIER}:latest ."
                }
            }
        }

        stage('Scan container images') {
            when { branch 'main' }
            steps {
                sh "trivy image --exit-code 1 --severity CRITICAL,HIGH --ignore-unfixed ${IMAGE_APP_TIER}:${IMAGE_TAG}"
                sh "trivy image --exit-code 1 --severity CRITICAL,HIGH --ignore-unfixed ${IMAGE_WEB_TIER}:${IMAGE_TAG}"
            }
        }

        stage('Push images to ECR') {
            when { branch 'main' }
            steps {
                // Jenkins EC2 host authenticates via its IAM instance role -- no stored keys.
                sh '''
                    aws ecr get-login-password --region $AWS_REGION | \
                        docker login --username AWS --password-stdin $REGISTRY
                    docker push ${IMAGE_APP_TIER}:${IMAGE_TAG}
                    docker push ${IMAGE_APP_TIER}:latest
                    docker push ${IMAGE_WEB_TIER}:${IMAGE_TAG}
                    docker push ${IMAGE_WEB_TIER}:latest
                '''
            }
        }

        stage('Deploy to staging') {
            when { branch 'main' }
            steps {
                sh "./scripts/ci-deploy.sh staging ${IMAGE_APP_TIER}:${IMAGE_TAG} ${IMAGE_WEB_TIER}:${IMAGE_TAG}"
            }
        }

        stage('Smoke test staging') {
            when { branch 'main' }
            steps {
                sh '''
                    STAGING_ALB=$(aws elbv2 describe-load-balancers --names ${PROJECT_NAME}-alb \
                        --region $AWS_REGION --query 'LoadBalancers[0].DNSName' --output text)
                    curl -sf "http://${STAGING_ALB}/health"
                '''
            }
        }

        // ---- Gate: a human must approve before production is touched ----
        stage('Approve production deployment') {
            when { branch 'main' }
            steps {
                timeout(time: 24, unit: 'HOURS') {
                    input message: "Deploy ${IMAGE_TAG} to PRODUCTION?",
                          submitter: 'release-managers',
                          ok: 'Deploy'
                }
            }
        }

        stage('Deploy to production') {
            when { branch 'main' }
            steps {
                // Same image tag that was already built, scanned, and
                // verified in staging -- never rebuilt for prod.
                sh "./scripts/ci-deploy.sh production ${IMAGE_APP_TIER}:${IMAGE_TAG} ${IMAGE_WEB_TIER}:${IMAGE_TAG}"
            }
        }
    }

    post {
        failure {
            script {
                withCredentials([string(credentialsId: 'notify-email', variable: 'NOTIFY_EMAIL')]) {
                    // sh """
                    //     curl -s -X POST -H 'Content-type: application/json' \
                    //       --data '{"text":":x: Build ${env.JOB_NAME} #${env.BUILD_NUMBER} failed on branch ${env.BRANCH_NAME}. ${env.BUILD_URL}"}' \
                    //       "\$SLACK_URL" || true
                    // """
                    emailext(
                        to: "${NOTIFY_EMAIL}",
                        subject: "FAILED: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                        body: "Pipeline failed on branch ${env.BRANCH_NAME}.\nDetails: ${env.BUILD_URL}"
                    )
                }
                // Also publish to the CloudWatch/SNS alert topic so failures
                // show up alongside infra alarms in one place.
                sh '''
                    TOPIC_ARN=$(aws sns list-topics --region $AWS_REGION \
                        --query "Topics[?contains(TopicArn, '${PROJECT_NAME}')].TopicArn | [0]" --output text)
                    if [ "$TOPIC_ARN" != "None" ]; then
                        aws sns publish --region $AWS_REGION --topic-arn "$TOPIC_ARN" \
                          --subject "Jenkins pipeline failed: ${JOB_NAME} #${BUILD_NUMBER}" \
                          --message "Branch ${BRANCH_NAME}. See ${BUILD_URL}" || true
                    fi
                '''
            }
        }
        always {
            cleanWs()
        }
    }
}

########################################
# Networking Outputs
########################################

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

########################################
# EC2 Outputs
########################################

output "ec2_instance_ids" {
  description = "IDs of the application EC2 instances"
  value       = aws_instance.app[*].id
}

output "ec2_private_ips" {
  description = "Private IPs of the application EC2 instances"
  value       = aws_instance.app[*].private_ip
}

########################################
# Load Balancer Outputs
########################################

output "alb_dns_name" {
  description = "Public DNS name of the load balancer - use this to access the app"
  value       = aws_lb.app.dns_name
}

output "alb_zone_id" {
  description = "Hosted zone ID of the ALB (useful for Route53 alias records)"
  value       = aws_lb.app.zone_id
}

########################################
# RDS Outputs
########################################

output "rds_endpoint" {
  description = "Connection endpoint for the RDS PostgreSQL instance"
  value       = aws_db_instance.postgres.endpoint
}

output "rds_db_name" {
  description = "Name of the initial database created on RDS"
  value       = aws_db_instance.postgres.db_name
}

########################################
# ECR Outputs
########################################

output "ecr_app_tier_repository_url" {
  description = "Push app-tier images here (Jenkins does this automatically)"
  value       = local.app_tier_repo_url
}

output "ecr_web_tier_repository_url" {
  description = "Push web-tier images here (Jenkins does this automatically)"
  value       = local.web_tier_repo_url
}

########################################
# Jenkins Outputs
########################################

output "jenkins_url" {
  description = "Jenkins UI (only reachable from jenkins_admin_cidr)"
  value       = var.is_primary_environment ? "http://${aws_instance.jenkins[0].public_ip}:8080" : null
}

output "jenkins_public_ip" {
  description = "Public IP of the Jenkins host, for SSH"
  value       = var.is_primary_environment ? aws_instance.jenkins[0].public_ip : null
}

########################################
# Monitoring Outputs
########################################

output "dashboard_infra_app_url" {
  description = "CloudWatch dashboard: infrastructure + application metrics"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.infra_app.dashboard_name}"
}

output "dashboard_database_url" {
  description = "CloudWatch dashboard: database metrics"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.database.dashboard_name}"
}

output "sns_alerts_topic_arn" {
  description = "SNS topic that alarms and Jenkins failure notifications publish to"
  value       = aws_sns_topic.alerts.arn
}

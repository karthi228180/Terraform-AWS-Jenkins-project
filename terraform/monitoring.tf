########################################
# CloudWatch agent config (installed on each app EC2 instance via user_data)
#   - Infra metrics: CPU, memory, disk (namespace "CWAgent")
#   - System logs: /var/log/messages, /var/log/secure
########################################

locals {
  cw_agent_config_app = jsonencode({
    agent = { metrics_collection_interval = 60 }
    metrics = {
      namespace = "CWAgent"
      append_dimensions = {
        InstanceId = "$${aws:InstanceId}"
      }
      metrics_collected = {
        cpu = {
          measurement                 = ["cpu_usage_idle", "cpu_usage_user", "cpu_usage_system"]
          metrics_collection_interval = 60
          totalcpu                    = true
        }
        mem = {
          measurement                 = ["mem_used_percent"]
          metrics_collection_interval = 60
        }
        disk = {
          measurement                 = ["used_percent"]
          metrics_collection_interval = 60
          resources                   = ["/"]
        }
      }
    }
    logs = {
      logs_collected = {
        files = {
          collect_list = [
            {
              file_path         = "/var/log/messages"
              log_group_name    = aws_cloudwatch_log_group.app_system.name
              log_stream_name   = "{instance_id}/messages"
              retention_in_days = var.log_retention_days
            },
            {
              file_path         = "/var/log/secure"
              log_group_name    = aws_cloudwatch_log_group.app_system.name
              log_stream_name   = "{instance_id}/secure"
              retention_in_days = var.log_retention_days
            }
          ]
        }
      }
    }
  })
}

########################################
# Centralized log groups
#   - application: app-tier container stdout (business logic logs)
#   - access:      web-tier/nginx container stdout (HTTP access logs)
#   - system:      OS-level logs from every app instance (CloudWatch agent)
########################################

resource "aws_cloudwatch_log_group" "app_application" {
  name              = "/${var.project_name}/${var.environment}/application"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "app_access" {
  name              = "/${var.project_name}/${var.environment}/access"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "app_system" {
  name              = "/${var.project_name}/${var.environment}/system"
  retention_in_days = var.log_retention_days
}

########################################
# ALB access logs -> S3 (separate from the app-level access log above;
# this is the load balancer's own record of every request)
########################################

resource "aws_s3_bucket" "alb_logs" {
  bucket        = "${var.project_name}-${var.environment}-alb-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket                  = aws_s3_bucket.alb_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter {}

    expiration { days = 30 }
  }
}

# ELB's regional log-delivery account (us-east-1). If you deploy to a
# different region, look up the matching account ID in the AWS docs for
# "Enable access logging" and update this.
data "aws_elb_service_account" "main" {}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = data.aws_elb_service_account.main.arn }
      Action    = "s3:PutObject"
      Resource  = "${aws_s3_bucket.alb_logs.arn}/alb/*"
    }]
  })
}

########################################
# SNS topic - alarms and Jenkins failure notifications both publish here
########################################

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-${var.environment}-alerts"
}

resource "aws_sns_topic_subscription" "alert_email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

########################################
# Alarms - infra, app (via ALB), and database
########################################

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  count               = var.instance_count
  alarm_name          = "${var.project_name}-${var.environment}-ec2-${count.index + 1}-high-cpu"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = { InstanceId = aws_instance.app[count.index].id }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "high_memory" {
  count               = var.instance_count
  alarm_name          = "${var.project_name}-${var.environment}-ec2-${count.index + 1}-high-memory"
  namespace           = "CWAgent"
  metric_name         = "mem_used_percent"
  dimensions          = { InstanceId = aws_instance.app[count.index].id }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 85
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "high_disk" {
  count               = var.instance_count
  alarm_name          = "${var.project_name}-${var.environment}-ec2-${count.index + 1}-high-disk"
  namespace           = "CWAgent"
  metric_name         = "disk_used_percent"
  dimensions          = { InstanceId = aws_instance.app[count.index].id, path = "/", device = "xvda1", fstype = "xfs" }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 85
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx_rate" {
  alarm_name          = "${var.project_name}-${var.environment}-alb-high-5xx"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = { LoadBalancer = aws_lb.app.arn_suffix }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 10
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "alb_high_latency" {
  alarm_name          = "${var.project_name}-${var.environment}-alb-high-latency"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  dimensions          = { LoadBalancer = aws_lb.app.arn_suffix }
  extended_statistic  = "p95"
  period              = 300
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "rds_high_cpu" {
  alarm_name          = "${var.project_name}-${var.environment}-rds-high-cpu"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = { DBInstanceIdentifier = aws_db_instance.postgres.id }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "rds_low_storage" {
  alarm_name          = "${var.project_name}-${var.environment}-rds-low-storage"
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  dimensions          = { DBInstanceIdentifier = aws_db_instance.postgres.id }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 1
  threshold           = 2000000000 # 2 GB
  comparison_operator = "LessThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "rds_high_connections" {
  alarm_name          = "${var.project_name}-${var.environment}-rds-high-connections"
  namespace           = "AWS/RDS"
  metric_name         = "DatabaseConnections"
  dimensions          = { DBInstanceIdentifier = aws_db_instance.postgres.id }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

########################################
# Dashboard 1: Infrastructure & Application
#   EC2 CPU/memory/disk + ALB request rate, error rate, latency
########################################

resource "aws_cloudwatch_dashboard" "infra_app" {
  dashboard_name = "${var.project_name}-${var.environment}-infra-and-app"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6,
        properties = {
          title   = "EC2 CPU Utilization (%)"
          view    = "timeSeries"
          region  = var.aws_region
          metrics = [for i in range(var.instance_count) : ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.app[i].id]]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6,
        properties = {
          title   = "EC2 Memory Used (%)"
          view    = "timeSeries"
          region  = var.aws_region
          metrics = [for i in range(var.instance_count) : ["CWAgent", "mem_used_percent", "InstanceId", aws_instance.app[i].id]]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6,
        properties = {
          title   = "EC2 Disk Used (%)"
          view    = "timeSeries"
          region  = var.aws_region
          metrics = [for i in range(var.instance_count) : ["CWAgent", "disk_used_percent", "InstanceId", aws_instance.app[i].id, "path", "/", "fstype", "xfs"]]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6,
        properties = {
          title   = "ALB Request Count"
          view    = "timeSeries"
          region  = var.aws_region
          stat    = "Sum"
          metrics = [["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.app.arn_suffix]]
        }
      },
      {
        type = "metric", x = 0, y = 12, width = 12, height = 6,
        properties = {
          title  = "ALB Error Rate (4XX / 5XX count)"
          view   = "timeSeries"
          region = var.aws_region
          stat   = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", "LoadBalancer", aws_lb.app.arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", aws_lb.app.arn_suffix]
          ]
        }
      },
      {
        type = "metric", x = 12, y = 12, width = 12, height = 6,
        properties = {
          title   = "ALB Target Response Time (Latency, seconds)"
          view    = "timeSeries"
          region  = var.aws_region
          stat    = "p95"
          metrics = [["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.app.arn_suffix]]
        }
      }
    ]
  })
}

########################################
# Dashboard 2: Database
########################################

resource "aws_cloudwatch_dashboard" "database" {
  dashboard_name = "${var.project_name}-${var.environment}-database"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6,
        properties = {
          title   = "RDS CPU Utilization (%)"
          view    = "timeSeries"
          region  = var.aws_region
          metrics = [["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.postgres.id]]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6,
        properties = {
          title   = "RDS Freeable Memory (Bytes)"
          view    = "timeSeries"
          region  = var.aws_region
          metrics = [["AWS/RDS", "FreeableMemory", "DBInstanceIdentifier", aws_db_instance.postgres.id]]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6,
        properties = {
          title   = "RDS Free Storage Space (Bytes)"
          view    = "timeSeries"
          region  = var.aws_region
          metrics = [["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", aws_db_instance.postgres.id]]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6,
        properties = {
          title   = "RDS Database Connections"
          view    = "timeSeries"
          region  = var.aws_region
          metrics = [["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", aws_db_instance.postgres.id]]
        }
      },
      {
        type = "metric", x = 0, y = 12, width = 12, height = 6,
        properties = {
          title  = "RDS Read / Write Latency (seconds)"
          view   = "timeSeries"
          region = var.aws_region
          metrics = [
            ["AWS/RDS", "ReadLatency", "DBInstanceIdentifier", aws_db_instance.postgres.id],
            ["AWS/RDS", "WriteLatency", "DBInstanceIdentifier", aws_db_instance.postgres.id]
          ]
        }
      },
      {
        type = "log", x = 12, y = 12, width = 12, height = 6,
        properties = {
          title  = "Recent PostgreSQL log errors"
          region = var.aws_region
          query  = "SOURCE '/aws/rds/instance/${aws_db_instance.postgres.id}/postgresql' | fields @timestamp, @message | filter @message like /ERROR/ | sort @timestamp desc | limit 20"
          view   = "table"
        }
      }
    ]
  })
}

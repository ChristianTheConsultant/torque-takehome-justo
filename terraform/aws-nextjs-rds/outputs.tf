output "app_url" {
  description = "Public URL of the Next.js app."
  value       = local.app_base_url
}

output "health_check_url" {
  description = "URL polled by the deployment health check."
  value       = "${local.app_base_url}${local.health_check_path}"
}

output "health_check_response" {
  description = "Body returned by the health check at deploy time (empty when wait_for_app is false)."
  value       = var.wait_for_app ? data.http.app_health[0].response_body : ""
}

output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.app.id
}

output "instance_public_ip" {
  description = "Public IPv4 address of the EC2 instance."
  value       = aws_instance.app.public_ip
}

output "ssm_session_command" {
  description = "AWS CLI command for a shell on the instance through Session Manager (no SSH needed)."
  value       = "aws ssm start-session --region ${var.region} --target ${aws_instance.app.id}"
}

output "rds_endpoint" {
  description = "RDS PostgreSQL hostname (private; reachable from the EC2 instance only)."
  value       = aws_db_instance.this.address
}

output "rds_database_name" {
  description = "Name of the application database."
  value       = aws_db_instance.this.db_name
}

output "database_url_parameter" {
  description = "SSM Parameter Store name holding the full DATABASE_URL (SecureString)."
  value       = aws_ssm_parameter.database_url.name
}

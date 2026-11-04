# RDS's password rules forbid '/', '@', '"' and spaces; alphanumeric also
# keeps the value safe inside a connection URL without escaping.
resource "random_password" "db" {
  length  = 32
  special = false
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.name_prefix}-db"
  subnet_ids = aws_subnet.private[*].id

  tags = { Name = "${var.name_prefix}-db" }
}

# Deliberately ephemeral and cheap: single-AZ, smallest storage, no automated
# backups, no final snapshot, no deletion protection. Do not reuse as-is for
# anything holding real data.
resource "aws_db_instance" "this" {
  identifier     = "${var.name_prefix}-db"
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage = var.db_allocated_storage_gb
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period      = 0
  skip_final_snapshot          = true
  deletion_protection          = false
  apply_immediately            = true
  auto_minor_version_upgrade   = true
  performance_insights_enabled = false

  tags = { Name = "${var.name_prefix}-db" }
}

# The instance reads this at boot via its IAM role, so the password never
# appears in user data, EC2 console output or Torque inputs. Standard-tier
# SecureString parameters with the AWS-managed key are free.
#
# RDS for PostgreSQL 15+ enforces TLS (rds.force_ssl=1). The bootstrap
# script installs the RDS CA bundle and points NODE_EXTRA_CA_CERTS at it, so
# sslmode=require verifies the server certificate under node-postgres.
resource "aws_ssm_parameter" "database_url" {
  name        = "/${var.name_prefix}/database-url"
  description = "PostgreSQL connection string for the ${var.name_prefix} Next.js app"
  type        = "SecureString"
  value       = "postgresql://${var.db_username}:${random_password.db.result}@${aws_db_instance.this.address}:${aws_db_instance.this.port}/${var.db_name}?sslmode=require"
}

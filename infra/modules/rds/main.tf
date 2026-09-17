resource "aws_security_group" "rds" {
  name        = "${var.name}-rds-sg"
  description = "RDS: Postgres ingress from the ECS tasks only"
  vpc_id      = var.vpc_id

  tags = {
    Name        = "${var.name}-rds-sg"
    Environment = var.environment
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "postgres_from_ecs" {
  security_group_id            = aws_security_group.rds.id
  description                  = "PostgreSQL from ECS tasks"
  referenced_security_group_id = var.ecs_security_group_id
  from_port                    = var.db_port
  to_port                      = var.db_port
  ip_protocol                  = "tcp"
}


resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name        = "${var.name}-db-subnet-group"
    Environment = var.environment
  }
}

resource "aws_db_parameter_group" "this" {
  name   = "${var.name}-pg"
  family = var.parameter_group_family

  # Log slow queries so the kind of query tuning done in the local database
  # task is also observable on RDS.
  parameter {
    name  = "log_min_duration_statement"
    value = tostring(var.log_min_duration_statement_ms)
  }

  tags = {
    Environment = var.environment
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "this" {
  identifier = "${var.name}-postgres"

  engine         = "postgres"
  engine_version = var.engine_version

  instance_class        = var.db_instance_class
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.database_name
  username = var.database_username

  manage_master_user_password = true

  port                 = var.db_port
  db_subnet_group_name = aws_db_subnet_group.this.name
  parameter_group_name = aws_db_parameter_group.this.name

  vpc_security_group_ids = [
    aws_security_group.rds.id
  ]

  publicly_accessible = false
  multi_az            = var.multi_az

  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window
  copy_tags_to_snapshot   = true

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name}-final-snapshot"

  maintenance_window         = var.maintenance_window
  auto_minor_version_upgrade = true
  apply_immediately          = var.apply_immediately

  performance_insights_enabled = var.performance_insights_enabled
  enabled_cloudwatch_logs_exports = [
    "postgresql",
    "upgrade",
  ]

  tags = {
    Name        = "${var.name}-postgres"
    Environment = var.environment
  }
}

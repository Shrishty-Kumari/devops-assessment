output "rds_endpoint" {
  description = "Private DNS address of the database. Only resolvable and reachable from inside the VPC."
  value       = aws_db_instance.this.address
}

output "rds_port" {
  description = "Port the database listens on."
  value       = aws_db_instance.this.port
}

output "rds_security_group_id" {
  description = "Database security group ID."
  value       = aws_security_group.rds.id
}

output "database_name" {
  description = "Name of the database created on the instance."
  value       = aws_db_instance.this.db_name
}

output "master_user_secret_arn" {
  description = "Secrets Manager secret holding the RDS-managed master credentials. The application reads the password from here."
  value       = try(aws_db_instance.this.master_user_secret[0].secret_arn, null)
}

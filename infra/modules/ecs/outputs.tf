output "ecs_security_group_id" {
  description = "Task security group ID. The RDS module allows Postgres ingress from this group only."
  value       = aws_security_group.ecs.id
}

output "alb_security_group_id" {
  description = "ALB security group ID."
  value       = aws_security_group.alb.id
}

output "alb_dns_name" {
  description = "Public DNS name of the ALB - the entry point to the application."
  value       = aws_lb.this.dns_name
}

output "cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.this.name
}

output "service_name" {
  description = "ECS service name."
  value       = aws_ecs_service.this.name
}

output "log_group_name" {
  description = "CloudWatch log group receiving container logs."
  value       = aws_cloudwatch_log_group.ecs.name
}

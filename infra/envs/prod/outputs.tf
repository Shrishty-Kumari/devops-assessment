output "alb_dns_name" {
  description = "Public entry point of the application."
  value       = module.ecs.alb_dns_name
}

output "ecs_cluster_name" {
  description = "ECS cluster name."
  value       = module.ecs.cluster_name
}

output "ecs_service_name" {
  description = "ECS service name."
  value       = module.ecs.service_name
}

output "rds_endpoint" {
  description = "Private database endpoint, reachable only from the ECS tasks."
  value       = module.rds.rds_endpoint
}

output "rds_master_user_secret_arn" {
  description = "Secrets Manager secret holding the RDS master credentials."
  value       = module.rds.master_user_secret_arn
}

output "vpc_id" {
  description = "VPC ID."
  value       = module.network.vpc_id
}

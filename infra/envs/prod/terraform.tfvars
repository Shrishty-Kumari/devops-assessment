environment = "prod"
aws_region  = "ap-south-1"

vpc_cidr = "10.20.0.0/16"
azs      = ["ap-south-1a", "ap-south-1b"]

single_nat_gateway = false

container_image = "nginx:alpine"
container_port  = 80

task_cpu      = 1024
task_memory   = 2048
desired_count = 2

log_retention_days      = 90
container_insights      = true
alb_deletion_protection = true

db_instance_class     = "db.t3.medium"
allocated_storage     = 100
max_allocated_storage = 500

database_name           = "hotel_booking"
database_username       = "app_user"
backup_retention_period = 30
multi_az                = true
deletion_protection     = true
skip_final_snapshot     = false

performance_insights_enabled = true
apply_immediately            = false 
environment = "dev"
aws_region  = "ap-south-1"

vpc_cidr           = "10.10.0.0/16"
azs                = ["ap-south-1a", "ap-south-1b"]
single_nat_gateway = true

container_image = "nginx:alpine"
container_port  = 80

task_cpu      = 256 # 0.25 vCPU
task_memory   = 512 # MiB
desired_count = 1

log_retention_days      = 7
container_insights      = false # extra cost, not needed in dev
alb_deletion_protection = false

db_instance_class     = "db.t3.micro"
allocated_storage     = 20
max_allocated_storage = 50

database_name     = "hotel_booking"
database_username = "app_user"

backup_retention_period = 3
multi_az                = false
deletion_protection     = false
skip_final_snapshot     = true

performance_insights_enabled = false
apply_immediately            = true

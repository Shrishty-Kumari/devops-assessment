terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  access_key                  = var.plan_only ? "mock-access-key" : var.aws_access_key
  secret_key                  = var.plan_only ? "mock-secret-key" : var.aws_secret_key
  skip_credentials_validation = var.plan_only
  skip_requesting_account_id  = var.plan_only
  skip_metadata_api_check     = var.plan_only

  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project
      ManagedBy   = "terraform"
    }
  }
}

locals {
  name = "${var.project}-${var.environment}"
}

module "network" {
  source = "../../modules/network"

  name        = local.name
  environment = var.environment

  vpc_cidr = var.vpc_cidr
  azs      = var.azs

  # dev accepts a single NAT gateway to keep the monthly cost down.
  single_nat_gateway = var.single_nat_gateway
}

module "ecs" {
  source = "../../modules/ecs"

  name        = local.name
  environment = var.environment
  aws_region  = var.aws_region

  vpc_id             = module.network.vpc_id
  public_subnet_ids  = module.network.public_subnet_ids
  private_subnet_ids = module.network.private_subnet_ids

  container_image = var.container_image
  container_port  = var.container_port

  task_cpu      = var.task_cpu
  task_memory   = var.task_memory
  desired_count = var.desired_count

  log_retention_days      = var.log_retention_days
  container_insights      = var.container_insights
  alb_deletion_protection = var.alb_deletion_protection
}

module "rds" {
  source = "../../modules/rds"

  name        = local.name
  environment = var.environment

  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids

  # This wiring is what restricts database access to the Fargate tasks.
  ecs_security_group_id = module.ecs.ecs_security_group_id

  db_instance_class     = var.db_instance_class
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage

  database_name     = var.database_name
  database_username = var.database_username

  backup_retention_period = var.backup_retention_period
  deletion_protection     = var.deletion_protection
  skip_final_snapshot     = var.skip_final_snapshot
  multi_az                = var.multi_az

  performance_insights_enabled = var.performance_insights_enabled
  apply_immediately            = var.apply_immediately
}

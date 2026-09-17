variable "name" {
  description = "Name prefix for all resources in this module."
  type        = string
}

variable "environment" {
  description = "Environment name, applied as a tag (dev, prod)."
  type        = string
}

variable "aws_region" {
  description = "Region for the awslogs driver. Passed in rather than read from a data source so plan works without AWS credentials."
  type        = string
}

variable "vpc_id" {
  description = "VPC the ALB, tasks and target group live in."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets for the ALB (needs at least two AZs)."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnets for the Fargate tasks."
  type        = list(string)
}

variable "container_name" {
  description = "Container name in the task definition. Must match the load balancer target."
  type        = string
  default     = "app"
}

variable "container_image" {
  description = "Container image to run. Any simple image works for this assessment (for example nginx:alpine)."
  type        = string
}

variable "container_port" {
  description = "Port the container listens on."
  type        = number
}

variable "health_check_path" {
  description = "HTTP path the target group health check requests."
  type        = string
  default     = "/"
}

variable "task_cpu" {
  description = "Fargate task CPU units (256 = 0.25 vCPU)."
  type        = number
}

variable "task_memory" {
  description = "Fargate task memory in MiB. Must be a valid pairing with task_cpu."
  type        = number
}

variable "desired_count" {
  description = "Number of tasks to run."
  type        = number

  validation {
    condition     = var.desired_count >= 1
    error_message = "desired_count must be at least 1."
  }
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for the task log group."
  type        = number
  default     = 30
}

variable "container_insights" {
  description = "Enable ECS Container Insights. Costs extra, so dev can turn it off."
  type        = bool
  default     = true
}

variable "alb_deletion_protection" {
  description = "Protect the ALB from accidental deletion. Should be true in prod."
  type        = bool
  default     = false
}

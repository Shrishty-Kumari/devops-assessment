variable "name" {
  description = "Name prefix for all resources in this module."
  type        = string
}

variable "environment" {
  description = "Environment name, applied as a tag (dev, prod)."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Must be large enough to carve /20 subnets out of."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block, for example 10.10.0.0/16."
  }
}

variable "azs" {
  description = "Availability zones to spread subnets across. One public and one private subnet is created per AZ."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2
    error_message = "At least two AZs are required: both the ALB and the RDS subnet group need two."
  }
}

variable "single_nat_gateway" {
  description = "Use one shared NAT gateway instead of one per AZ. Cheaper, but a single point of failure - intended for dev."
  type        = bool
  default     = false
}

variable "aws_region" {
  description = "Region for the state bucket and lock table. Must match the region in infra/envs/*/backend.tf."
  type        = string
  default     = "ap-south-1"
}

variable "state_bucket_name" {
  description = "Name of the S3 bucket to hold Terraform state. S3 bucket names are globally unique, so this must be a name nobody else has taken."
  type        = string

  // S3 rejects uppercase and underscores, and the name must be 3-63 chars.
  // Catching it here beats finding out at apply time.
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.state_bucket_name))
    error_message = "state_bucket_name must be 3-63 characters, lowercase letters, digits, dots or hyphens, and start and end alphanumeric."
  }
}

variable "lock_table_name" {
  description = "Name of the DynamoDB table used for state locking."
  type        = string
  default     = "terraform-state-lock"
}

variable "noncurrent_version_retention_days" {
  description = "How long to keep superseded state versions before expiring them."
  type        = number
  default     = 90
}

variable "plan_only" {
  description = "Use placeholder AWS credentials so `terraform plan` works without AWS access. Set to false to actually create the bucket and table."
  type        = bool
  default     = true
}

variable "aws_access_key" {
  description = "AWS access key ID. Leave null to use AWS_ACCESS_KEY_ID or an AWS profile. Only read when plan_only = false. Never commit a real value."
  type        = string
  default     = null
  sensitive   = true
}

variable "aws_secret_key" {
  description = "AWS secret access key. Leave null to use AWS_SECRET_ACCESS_KEY or an AWS profile. Only read when plan_only = false. Never commit a real value."
  type        = string
  default     = null
  sensitive   = true
}

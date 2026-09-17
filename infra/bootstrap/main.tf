// Creates the S3 bucket and DynamoDB lock table that infra/envs/*/backend.tf
// use for remote state.
//
// This config deliberately has NO backend block of its own, so it uses local
// state: Terraform cannot store its state in the bucket it is in the middle of
// creating. It is applied once, by hand, before either environment.
//
// Run order:
//   1. cd infra/bootstrap && terraform apply -var plan_only=false
//   2. put the output names into infra/envs/*/backend.tf
//   3. delete infra/envs/*/backend_override.tf
//   4. cd ../envs/dev && terraform init -migrate-state

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

  // Same plan-only switch as the environments, so this config can be reviewed
  // offline. Set plan_only = false to actually create the bucket and table.
  access_key                  = var.plan_only ? "mock-access-key" : var.aws_access_key
  secret_key                  = var.plan_only ? "mock-secret-key" : var.aws_secret_key
  skip_credentials_validation = var.plan_only
  skip_requesting_account_id  = var.plan_only
  skip_metadata_api_check     = var.plan_only

  default_tags {
    tags = {
      Project   = "hotel-booking"
      Purpose   = "terraform-remote-state"
      ManagedBy = "terraform"
    }
  }
}

resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket_name

  // State is the only record of what exists in AWS. Losing it is worse than
  // almost any other failure in this repo, so the bucket refuses to be
  // destroyed by Terraform. Remove this block if you really need to delete it.
  lifecycle {
    prevent_destroy = true
  }
}

// Versioning is what makes a corrupted or truncated state recoverable: every
// write keeps the previous object version.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

// State contains resource attributes and should never be world-readable.
resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

// Versioning grows forever without this; old state versions are only useful
// for recovery, so they expire after a retention window.
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-noncurrent-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

// State locking: stops two applies (a merge and a manual run, say) from
// writing state at the same time. The hash key must be named exactly LockID,
// which is what the s3 backend looks for.
resource "aws_dynamodb_table" "lock" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }
}

output "state_bucket" {
  description = "S3 bucket holding Terraform state. Set this as the GitHub repository variable TF_STATE_BUCKET."
  value       = aws_s3_bucket.state.id
}

output "lock_table" {
  description = "DynamoDB table used for state locking. Set this as the GitHub repository variable TF_LOCK_TABLE."
  value       = aws_dynamodb_table.lock.name
}

output "backend_config" {
  description = "Ready-to-paste backend block for infra/envs/<env>/backend.tf. Replace <env> with dev or prod."
  value       = <<-EOT
    terraform {
      backend "s3" {
        bucket         = "${aws_s3_bucket.state.id}"
        key            = "hotel-booking/<env>/terraform.tfstate"
        region         = "${var.aws_region}"
        dynamodb_table = "${aws_dynamodb_table.lock.name}"
        encrypt        = true
      }
    }
  EOT
}

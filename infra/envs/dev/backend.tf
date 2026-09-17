// Remote state for dev. Separate key per environment, so dev and prod can
// never read or overwrite each other's state.
//
// The bucket and lock table are created by infra/bootstrap. If you change
// state_bucket_name there, change `bucket` here and in ../prod/backend.tf to
// match.
//
// NOTE FOR REVIEW: backend_override.tf in this directory switches Terraform to
// a local backend so `terraform init` works without an S3 bucket or AWS
// credentials. Delete that file to use this configuration for real.
terraform {
  backend "s3" {
    bucket         = "hotel-booking-tfstate-changeme"
    key            = "hotel-booking/dev/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "hotel-booking-terraform-lock"
    encrypt        = true
  }
}

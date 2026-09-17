terraform {
  backend "s3" {
    bucket         = "hotel-booking-tfstate-assignment"
    key            = "hotel-booking/dev/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "hotel-booking-terraform-lock"
    encrypt        = true
  }
}

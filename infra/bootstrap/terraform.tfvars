aws_region = "ap-south-1"

# S3 bucket names are globally unique, so this WILL collide as-is. Change it to
# something nobody else has taken before applying - appending your AWS account
# id or initials is the usual trick.
state_bucket_name = "hotel-booking-tfstate-changeme"
lock_table_name   = "hotel-booking-terraform-lock"

noncurrent_version_retention_days = 90

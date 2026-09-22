# Remote state for the dev environment. Bucket and table are created by
# terraform/bootstrap. Rename this file to backend.tf and run
# `terraform init -migrate-state` to move local state into S3.
terraform {
  backend "s3" {
    bucket         = "crra-tfstate-066396400145"
    key            = "dev/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "crra-tfstate-lock"
    encrypt        = true
  }
}

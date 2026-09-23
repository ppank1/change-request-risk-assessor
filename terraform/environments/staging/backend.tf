# Remote state for the staging environment. Same bucket and lock table as dev
# (created by terraform/bootstrap), different key -- so dev and staging are
# locked and versioned independently and one cannot clobber the other.
terraform {
  backend "s3" {
    bucket         = "crra-tfstate-066396400145"
    key            = "staging/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "crra-tfstate-lock"
    encrypt        = true
  }
}

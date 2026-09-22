output "state_bucket" {
  description = "S3 bucket holding Terraform state for all environments."
  value       = aws_s3_bucket.state.bucket
}

output "lock_table" {
  description = "DynamoDB table used for state locking."
  value       = aws_dynamodb_table.lock.name
}

output "region" {
  value = var.region
}

output "backend_config" {
  description = "Paste into each environment's backend.tf, changing only the key."
  value       = <<-EOT
    terraform {
      backend "s3" {
        bucket         = "${aws_s3_bucket.state.bucket}"
        key            = "<environment>/terraform.tfstate"
        region         = "${var.region}"
        dynamodb_table = "${aws_dynamodb_table.lock.name}"
        encrypt        = true
      }
    }
  EOT
}

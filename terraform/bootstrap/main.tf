# Terraform state backend for CRRA.
#
# This configuration uses LOCAL state on purpose: it creates the bucket and
# lock table that every other configuration stores its state in, so it cannot
# depend on them. Run once per AWS account; keep its local .tfstate committed
# out of the repo (see .gitignore) and backed up.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      ManagedBy   = "terraform"
      Environment = "shared"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  # Account ID in the name keeps the bucket globally unique without a random suffix.
  bucket_name = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"
  table_name  = "${var.project}-tfstate-lock"
}

# --- State bucket -----------------------------------------------------------

# Accepted risk: server access logging needs a second bucket to log into,
# doubling the bootstrap footprint. State access is already recorded by
# CloudTrail and every write is kept as an object version below.
#tfsec:ignore:aws-s3-enable-bucket-logging
resource "aws_s3_bucket" "state" {
  bucket = local.bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

# Every write to the state file is kept as a version, so a bad apply can be rolled back.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Accepted risk: SSE-S3 (AES256) encrypts state at rest; a customer-managed
# KMS key adds a key policy and a monthly cost for no change in who can read
# the bucket, which is governed by IAM and the TLS-only bucket policy.
#tfsec:ignore:aws-s3-encryption-customer-key
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# State contains resource IDs and can contain secrets: refuse plaintext HTTP.
resource "aws_s3_bucket_policy" "state_tls_only" {
  bucket = aws_s3_bucket.state.id

  # Public access block must exist before a bucket policy is attached.
  depends_on = [aws_s3_bucket_public_access_block.state]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.state.arn,
          "${aws_s3_bucket.state.arn}/*",
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }
    ]
  })
}

# --- Lock table -------------------------------------------------------------

# Accepted risk: the table holds only lock IDs and digests, encrypted with
# the AWS-owned key; a customer key protects nothing extra here.
#tfsec:ignore:aws-dynamodb-table-customer-key
resource "aws_dynamodb_table" "lock" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  point_in_time_recovery {
    enabled = true
  }
}

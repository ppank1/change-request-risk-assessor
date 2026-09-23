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

  # Applied to every resource. Project is also the Ansible dynamic-inventory
  # filter, so a host is in inventory purely by being Terraform-managed.
  default_tags {
    tags = {
      Project     = var.project
      ManagedBy   = "terraform"
      Environment = var.environment
    }
  }
}

data "aws_caller_identity" "current" {}

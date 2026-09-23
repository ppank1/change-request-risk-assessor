variable "vpc_cidr" {
  type = string
}

variable "public_subnet_cidr" {
  type = string
}

variable "availability_zone" {
  type = string
}

variable "flow_log_name" {
  type        = string
  description = "Name for the VPC flow log role and log group"
  default     = "crra-vpc-flow-logs"
}

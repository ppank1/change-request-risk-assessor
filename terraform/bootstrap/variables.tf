variable "region" {
  description = "AWS region for the state backend. Must match the region used in every backend.tf."
  type        = string
  default     = "us-west-2"
}

variable "project" {
  description = "Project slug used in resource names and the Project tag."
  type        = string
  default     = "crra"
}

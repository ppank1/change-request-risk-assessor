variable "region" {
  type    = string
  default = "us-west-2"
}

variable "project" {
  type    = string
  default = "crra"
}

variable "environment" {
  type    = string
  default = "dev"
}

# network
variable "vpc_cidr" {
  type = string
}

variable "public_subnet_cidr" {
  type = string
}

variable "availability_zone" {
  type = string
}

# security
variable "admin_cidrs" {
  type = map(object({
    cidr        = string
    description = optional(string)
  }))
}

variable "jenkins_agent_cidr" {
  type    = string
  default = "0.0.0.0/0"
}

# compute
variable "ami_id" {
  type = string
}

variable "key_name" {
  type = string
}

variable "jenkins" {
  type = object({
    name           = string
    instance_type  = string
    private_ip     = string
    root_volume_gb = number
  })
}

variable "k3s" {
  type = object({
    name           = string
    instance_type  = string
    private_ip     = string
    root_volume_gb = number
  })
}

variable "test_instance" {
  description = "Disposable instance for the immutability demonstration. Leave null except during the demo."
  type = object({
    name          = string
    instance_type = string
  })
  default = null
}

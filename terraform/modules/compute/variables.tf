variable "ami_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "key_name" {
  type = string
}

variable "public_key" {
  description = "OpenSSH public key for the key pair. Private key never enters Terraform."
  type        = string
}

variable "jenkins_sg_id" {
  type = string
}

variable "k3s_sg_id" {
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

variable "baseline_user_data" {
  description = "Attach the baseline bootstrap user_data to the Jenkins and k3s hosts. Enabling this on existing hosts rebuilds them."
  type        = bool
  default     = false
}

variable "test_instance" {
  description = "Disposable instance for replacement demonstrations. null = not created."
  type = object({
    name          = string
    instance_type = string
  })
  default = null
}

variable "test_sg_id" {
  description = "Security group for the disposable test instance."
  type        = string
  default     = null
}

variable "instance_profile_name" {
  description = "IAM instance profile attached to every host (SSM Session Manager access)."
  type        = string
  default     = null
}

variable "jenkins_instance_profile_name" {
  description = "IAM instance profile for the Jenkins host; falls back to instance_profile_name."
  type        = string
  default     = null
}

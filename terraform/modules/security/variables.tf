variable "vpc_id" {
  type = string
}

variable "name_prefix" {
  description = "Prefix for IAM roles, instance profiles and the test SG. IAM names are account-global, so a second environment in the same account needs its own prefix."
  type        = string
  default     = "crra"
}

variable "jenkins_sg_name" {
  type    = string
  default = "crra-jenkins-sg"
}

variable "k3s_sg_name" {
  type    = string
  default = "crra-k3s-sg"
}

variable "admin_cidrs" {
  description = "Client CIDRs allowed SSH, Jenkins UI and k3s NodePort access. Key is a stable label used in state addresses."
  type = map(object({
    cidr        = string
    description = optional(string)
  }))
}

variable "jenkins_agent_cidr" {
  description = "Source CIDR allowed to reach the Jenkins JNLP agent port (50000). null = no agents, port closed."
  type        = string
  default     = null
}

variable "jenkins_private_ip" {
  description = "Private IP of the Jenkins host, the only source allowed to reach the k3s API."
  type        = string
}

variable "tfstate_bucket_arn" {
  description = "ARN of the Terraform remote-state bucket the Jenkins CI role may read."
  type        = string
}

variable "tfstate_lock_table_arn" {
  description = "ARN of the DynamoDB lock table the Jenkins CI role may lock."
  type        = string
}

variable "secret_parameter_arns" {
  description = "SSM SecureString parameter ARNs the Jenkins CI role may read. Empty disables the statements."
  type        = list(string)
  default     = []
}

variable "secrets_kms_key_arn" {
  description = "KMS key that encrypts the parameters above (the SSM default key). Required when secret_parameter_arns is non-empty."
  type        = string
  default     = null
}

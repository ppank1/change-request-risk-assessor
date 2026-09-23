# Runtime secrets live in SSM Parameter Store as SecureString, created once by
# an operator (see docs/runbook.md "Secrets") -- never in git, tfvars or state.
#
# Terraform reads them WITHOUT decryption: it needs the ARN, to grant the
# Jenkins CI role read access to exactly these parameters, and the type, to
# refuse a plan if a secret was ever stored as a plain String. The value in
# state is the KMS ciphertext, useless without kms:Decrypt on the SSM key.

locals {
  secret_parameters = {
    grafana_admin_password = "/${var.project}/${var.environment}/grafana/admin_password"
    app_api_token          = "/${var.project}/${var.environment}/app/api_token"
  }
}

data "aws_ssm_parameter" "secret" {
  for_each        = local.secret_parameters
  name            = each.value
  with_decryption = false

  lifecycle {
    postcondition {
      condition     = self.type == "SecureString"
      error_message = "${each.value} must be a SecureString; a plain String parameter is not an acceptable place for a secret."
    }
  }
}

# The default SSM key encrypts these parameters; readers also need kms:Decrypt on it.
data "aws_kms_alias" "ssm" {
  name = "alias/aws/ssm"
}

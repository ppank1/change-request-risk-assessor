# Security layer: security groups for the Jenkins and k3s hosts.
# Rules are one resource each (aws_vpc_security_group_*_rule) so every rule
# has its own state address and can be imported or changed individually.

resource "aws_security_group" "jenkins" {
  name        = var.jenkins_sg_name
  description = var.jenkins_sg_name
  vpc_id      = var.vpc_id
}

resource "aws_security_group" "k3s" {
  name        = var.k3s_sg_name
  description = var.k3s_sg_name
  vpc_id      = var.vpc_id
}

# --- Jenkins host -----------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "jenkins_ssh" {
  for_each          = var.admin_cidrs
  security_group_id = aws_security_group.jenkins.id
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = each.value.cidr
  description       = each.value.description
}

resource "aws_vpc_security_group_ingress_rule" "jenkins_ui" {
  for_each          = var.admin_cidrs
  security_group_id = aws_security_group.jenkins.id
  ip_protocol       = "tcp"
  from_port         = 8080
  to_port           = 8080
  cidr_ipv4         = each.value.cidr
  description       = each.value.description
}

# JNLP agent port. Found open to the world on import; tightening it is a
# deliberate follow-up change, not part of the import.
# JNLP agent port. Only created when an agent CIDR is given: this Jenkins has
# no build agents (the controller runs every stage), so the port stays closed.
resource "aws_vpc_security_group_ingress_rule" "jenkins_agent" {
  count = var.jenkins_agent_cidr == null ? 0 : 1

  security_group_id = aws_security_group.jenkins.id
  ip_protocol       = "tcp"
  from_port         = 50000
  to_port           = 50000
  cidr_ipv4         = var.jenkins_agent_cidr
  description       = "Jenkins inbound agents (JNLP)"
}

resource "aws_vpc_security_group_egress_rule" "jenkins_all" {
  security_group_id = aws_security_group.jenkins.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# --- Monitoring UIs (Prometheus + Grafana run on the Jenkins host) -----------

resource "aws_vpc_security_group_ingress_rule" "prometheus_ui" {
  for_each          = var.admin_cidrs
  security_group_id = aws_security_group.jenkins.id
  ip_protocol       = "tcp"
  from_port         = 9090
  to_port           = 9090
  cidr_ipv4         = each.value.cidr
  description       = each.value.description
}

resource "aws_vpc_security_group_ingress_rule" "grafana_ui" {
  for_each          = var.admin_cidrs
  security_group_id = aws_security_group.jenkins.id
  ip_protocol       = "tcp"
  from_port         = 3000
  to_port           = 3000
  cidr_ipv4         = each.value.cidr
  description       = each.value.description
}

# --- k3s host ---------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "k3s_ssh" {
  for_each          = var.admin_cidrs
  security_group_id = aws_security_group.k3s.id
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = each.value.cidr
  description       = each.value.description
}

resource "aws_vpc_security_group_ingress_rule" "k3s_nodeport" {
  for_each          = var.admin_cidrs
  security_group_id = aws_security_group.k3s.id
  ip_protocol       = "tcp"
  from_port         = 30000
  to_port           = 32767
  cidr_ipv4         = each.value.cidr
  description       = each.value.description
}

# Kubernetes API, reachable only from the Jenkins host's private IP.
resource "aws_vpc_security_group_ingress_rule" "k3s_api_from_jenkins" {
  security_group_id = aws_security_group.k3s.id
  ip_protocol       = "tcp"
  from_port         = 6443
  to_port           = 6443
  cidr_ipv4         = "${var.jenkins_private_ip}/32"
}

# Prometheus (on the Jenkins host) scrapes the app's /metrics via NodePort 30000.
resource "aws_vpc_security_group_ingress_rule" "k3s_app_scrape_from_jenkins" {
  security_group_id = aws_security_group.k3s.id
  ip_protocol       = "tcp"
  from_port         = 30000
  to_port           = 30000
  cidr_ipv4         = "${var.jenkins_private_ip}/32"
  description       = "Prometheus scrape of the CRRA app"
}

# Prometheus scrapes node_exporter on the k3s host. Missing on first rollout:
# the target showed DOWN with "i/o timeout" until this rule was added.
resource "aws_vpc_security_group_ingress_rule" "k3s_node_exporter_from_jenkins" {
  security_group_id = aws_security_group.k3s.id
  ip_protocol       = "tcp"
  from_port         = 9100
  to_port           = 9100
  cidr_ipv4         = "${var.jenkins_private_ip}/32"
  description       = "Prometheus scrape of node_exporter"
}

resource "aws_vpc_security_group_egress_rule" "k3s_all" {
  security_group_id = aws_security_group.k3s.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# --- Disposable test host ---------------------------------------------------
# SSH plus the :8000 bootstrap health marker, admin CIDRs only.

resource "aws_security_group" "test" {
  name        = "${var.name_prefix}-test-sg"
  description = "${var.name_prefix}-test-sg"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "test_ssh" {
  for_each          = var.admin_cidrs
  security_group_id = aws_security_group.test.id
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = each.value.cidr
  description       = each.value.description
}

resource "aws_vpc_security_group_ingress_rule" "test_health" {
  for_each          = var.admin_cidrs
  security_group_id = aws_security_group.test.id
  ip_protocol       = "tcp"
  from_port         = 8000
  to_port           = 8000
  cidr_ipv4         = each.value.cidr
  description       = each.value.description
}

resource "aws_vpc_security_group_egress_rule" "test_all" {
  security_group_id = aws_security_group.test.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# --- Instance IAM role -------------------------------------------------------
# Lets hosts register with Systems Manager so Ansible/SSH reach them through
# Session Manager over 443 instead of an internet-exposed port 22.

data "aws_iam_policy_document" "instance_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "${var.name_prefix}-instance-role"
  assume_role_policy = data.aws_iam_policy_document.instance_assume.json
}

resource "aws_iam_role_policy_attachment" "instance_ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.name_prefix}-instance-profile"
  role = aws_iam_role.instance.name
}

# --- Jenkins CI role ----------------------------------------------------------
# The pipeline runs `terraform plan` and `ansible-playbook` from the Jenkins
# host. It uses this instance role rather than access keys stored in Jenkins:
# nothing long-lived to leak or rotate, and the grant is exactly what those
# two commands need. No write to AWS resources -- apply stays a human action.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_iam_role" "jenkins" {
  name               = "${var.name_prefix}-jenkins-role"
  assume_role_policy = data.aws_iam_policy_document.instance_assume.json
}

resource "aws_iam_role_policy_attachment" "jenkins_ssm" {
  role       = aws_iam_role.jenkins.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "jenkins_ci" {
  # Terraform remote state: read the state object, take and release the lock.
  statement {
    sid       = "TerraformStateRead"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [var.tfstate_bucket_arn, "${var.tfstate_bucket_arn}/*"]
  }
  statement {
    sid       = "TerraformStateLock"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [var.tfstate_lock_table_arn]
  }

  # Terraform plan refreshes every managed resource; these are read-only.
  # EC2 Describe* calls do not support resource-level permissions, so "*" is
  # the only valid resource, and plan needs the whole Describe family.
  #tfsec:ignore:aws-iam-no-policy-wildcards
  statement {
    sid = "TerraformPlanRead"
    actions = [
      "ec2:Describe*",
      "iam:GetRole",
      "iam:GetInstanceProfile",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      # VPC flow-log group; DescribeLogGroups has no resource-level scope.
      "logs:DescribeLogGroups",
      "logs:ListTagsForResource",
    ]
    resources = ["*"]
  }

  # Ansible: dynamic inventory + SSH over Session Manager, CRRA hosts only.
  statement {
    sid       = "AnsibleInventory"
    actions   = ["ssm:DescribeInstanceInformation", "ssm:DescribeSessions", "ssm:GetConnectionStatus"]
    resources = ["*"]
  }
  statement {
    sid       = "AnsibleSessionTarget"
    actions   = ["ssm:StartSession"]
    resources = ["arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*"]
    condition {
      test     = "StringEquals"
      variable = "ssm:resourceTag/Project"
      values   = ["crra"]
    }
  }
  statement {
    sid       = "AnsibleSessionDocument"
    actions   = ["ssm:StartSession"]
    resources = ["arn:aws:ssm:${data.aws_region.current.name}::document/AWS-StartSSHSession"]
  }
  # Session IDs are generated when a session starts, so the ARN can only be
  # scoped to this account and region, not to a named session.
  statement {
    sid       = "AnsibleSessionLifecycle"
    actions   = ["ssm:TerminateSession", "ssm:ResumeSession"]
    resources = ["arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:session/*"]
  }
  # Runtime secrets for the Configuration Management stage: read exactly the
  # named parameters, decrypt with the SSM key only. No PutParameter -- the
  # pipeline consumes secrets, operators rotate them.
  dynamic "statement" {
    for_each = length(var.secret_parameter_arns) > 0 ? [1] : []
    content {
      sid       = "ReadRuntimeSecrets"
      actions   = ["ssm:GetParameter", "ssm:GetParameters"]
      resources = var.secret_parameter_arns
    }
  }
  dynamic "statement" {
    for_each = length(var.secret_parameter_arns) > 0 ? [1] : []
    content {
      sid       = "DecryptRuntimeSecrets"
      actions   = ["kms:Decrypt"]
      resources = [var.secrets_kms_key_arn]
      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["ssm.${data.aws_region.current.name}.amazonaws.com"]
      }
    }
  }
}

resource "aws_iam_role_policy" "jenkins_ci" {
  name   = "${var.name_prefix}-jenkins-ci"
  role   = aws_iam_role.jenkins.id
  policy = data.aws_iam_policy_document.jenkins_ci.json
}

resource "aws_iam_instance_profile" "jenkins" {
  name = "${var.name_prefix}-jenkins-profile"
  role = aws_iam_role.jenkins.name
}

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
resource "aws_vpc_security_group_ingress_rule" "jenkins_agent" {
  security_group_id = aws_security_group.jenkins.id
  ip_protocol       = "tcp"
  from_port         = 50000
  to_port           = 50000
  cidr_ipv4         = var.jenkins_agent_cidr
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
  name        = "crra-test-sg"
  description = "crra-test-sg"
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
  name               = "crra-instance-role"
  assume_role_policy = data.aws_iam_policy_document.instance_assume.json
}

resource "aws_iam_role_policy_attachment" "instance_ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "instance" {
  name = "crra-instance-profile"
  role = aws_iam_role.instance.name
}

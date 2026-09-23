# Network layer: one VPC, one public subnet, internet gateway and the VPC's
# main route table. Written to also describe an existing default VPC exactly,
# so it can be imported without changes.

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  instance_tenancy     = "default"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "aws_subnet" "public_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidr
  availability_zone = var.availability_zone
  # Hosts that need a public address get an explicit Elastic IP; nothing else
  # launched here should be reachable from the internet by default.
  map_public_ip_on_launch = false

  private_dns_hostname_type_on_launch            = "ip-name"
  enable_resource_name_dns_a_record_on_launch    = false
  enable_resource_name_dns_aaaa_record_on_launch = false
}

# --- VPC flow logs ----------------------------------------------------------
# Accepted/rejected traffic for every interface in the VPC, kept 30 days in
# CloudWatch Logs. Needed to answer "who talked to what" after an incident.

# AWS-managed encryption at rest is sufficient for flow-log metadata; a
# customer-managed KMS key would add cost and a key policy to operate.
#tfsec:ignore:aws-cloudwatch-log-group-customer-key
resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/aws/vpc/${var.flow_log_name}"
  retention_in_days = 30
}

data "aws_iam_policy_document" "flow_logs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "flow_logs_write" {
  # Log streams are created per network interface at runtime, so the
  # stream ARN can only be expressed as <this log group>:*.
  #tfsec:ignore:aws-iam-no-policy-wildcards
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.flow_logs.arn}:*"]
  }
}

resource "aws_iam_role" "flow_logs" {
  name               = var.flow_log_name
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume.json
}

resource "aws_iam_role_policy" "flow_logs" {
  name   = "write-flow-logs"
  role   = aws_iam_role.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs_write.json
}

resource "aws_flow_log" "main" {
  vpc_id          = aws_vpc.main.id
  traffic_type    = "ALL"
  log_destination = aws_cloudwatch_log_group.flow_logs.arn
  iam_role_arn    = aws_iam_role.flow_logs.arn
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

resource "aws_default_route_table" "main" {
  default_route_table_id = aws_vpc.main.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

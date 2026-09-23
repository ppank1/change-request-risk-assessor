# staging environment values. Same modules as dev, different data: its own
# VPC so nothing overlaps with dev's 172.31.0.0/16, and smaller instances.
# Nothing here is imported -- a `terraform apply` of this root creates a
# complete second copy of the estate from scratch.

vpc_cidr           = "10.20.0.0/16"
public_subnet_cidr = "10.20.1.0/24"
availability_zone  = "us-west-2a"

# Same operators as dev; kept in each environment's tfvars deliberately so a
# staging-only widening never leaks into dev.
admin_cidrs = {
  home    = { cidr = "15.248.0.0/22", description = "Corporate VPN egress (NAT pool)" }
  devdesk = { cidr = "54.240.197.0/24", description = "DevDesktop" }
}

ami_id   = "ami-096f5760b00bcd95c" # Ubuntu 24.04 LTS, us-west-2 (same as dev)
key_name = "crra-staging-key"

# One size down from dev on both hosts; the staging cluster runs the same
# manifests with replicas: 1.
jenkins = {
  name           = "crra-staging-jenkins-001"
  instance_type  = "t3.small"
  private_ip     = "10.20.1.10"
  root_volume_gb = 20
}

k3s = {
  name           = "crra-staging-k3s-001"
  instance_type  = "t3.micro"
  private_ip     = "10.20.1.20"
  root_volume_gb = 15
}

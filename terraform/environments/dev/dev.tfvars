# dev environment values. Everything here describes the live infrastructure
# as imported; changing a value here is a change to real infrastructure.

vpc_cidr           = "172.31.0.0/16"
public_subnet_cidr = "172.31.32.0/20"
availability_zone  = "us-west-2a"

# Clients allowed SSH / Jenkins UI / k3s NodePort access.
# "home" was a single VPN egress address (15.248.3.5/32) that went stale when the
# VPN moved the client to 15.248.3.113 -- allow the egress range instead.
admin_cidrs = {
  home    = { cidr = "15.248.3.0/24", description = "Corporate VPN egress" }
  devdesk = { cidr = "54.240.197.0/24", description = "DevDesktop" }
}

ami_id   = "ami-096f5760b00bcd95c" # Ubuntu 24.04 LTS, us-west-2
key_name = "crra-key"

jenkins = {
  name           = "crra-jenkins-001"
  instance_type  = "t3.medium"
  private_ip     = "172.31.46.173"
  root_volume_gb = 20
}

k3s = {
  name           = "crra-k3s-001"
  instance_type  = "t3.small"
  private_ip     = "172.31.37.73"
  root_volume_gb = 15
}

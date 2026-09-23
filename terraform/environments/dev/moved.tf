# Refactor record: flat resources -> modules. Each block tells Terraform the
# resource at the old address is the same object as the one at the new
# address, so the plan shows a move, not a destroy + create.
# Equivalent to `terraform state mv`, but reviewable and applied by the plan.
# Safe to delete once every environment has applied it.

# network
moved {
  from = aws_vpc.main
  to   = module.network.aws_vpc.main
}

moved {
  from = aws_subnet.public_a
  to   = module.network.aws_subnet.public_a
}

moved {
  from = aws_internet_gateway.main
  to   = module.network.aws_internet_gateway.main
}

moved {
  from = aws_default_route_table.main
  to   = module.network.aws_default_route_table.main
}

# security
moved {
  from = aws_security_group.jenkins
  to   = module.security.aws_security_group.jenkins
}

moved {
  from = aws_security_group.k3s
  to   = module.security.aws_security_group.k3s
}

moved {
  from = aws_vpc_security_group_ingress_rule.jenkins_ssh
  to   = module.security.aws_vpc_security_group_ingress_rule.jenkins_ssh
}

moved {
  from = aws_vpc_security_group_ingress_rule.jenkins_ui
  to   = module.security.aws_vpc_security_group_ingress_rule.jenkins_ui
}

moved {
  from = aws_vpc_security_group_ingress_rule.jenkins_agent
  to   = module.security.aws_vpc_security_group_ingress_rule.jenkins_agent
}

moved {
  from = aws_vpc_security_group_egress_rule.jenkins_all
  to   = module.security.aws_vpc_security_group_egress_rule.jenkins_all
}

moved {
  from = aws_vpc_security_group_ingress_rule.k3s_ssh
  to   = module.security.aws_vpc_security_group_ingress_rule.k3s_ssh
}

moved {
  from = aws_vpc_security_group_ingress_rule.k3s_nodeport
  to   = module.security.aws_vpc_security_group_ingress_rule.k3s_nodeport
}

moved {
  from = aws_vpc_security_group_ingress_rule.k3s_api_from_jenkins
  to   = module.security.aws_vpc_security_group_ingress_rule.k3s_api_from_jenkins
}

moved {
  from = aws_vpc_security_group_egress_rule.k3s_all
  to   = module.security.aws_vpc_security_group_egress_rule.k3s_all
}

# compute
moved {
  from = aws_key_pair.crra
  to   = module.compute.aws_key_pair.this
}

moved {
  from = aws_instance.jenkins
  to   = module.compute.aws_instance.jenkins
}

moved {
  from = aws_instance.k3s
  to   = module.compute.aws_instance.k3s
}

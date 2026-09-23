module "network" {
  source = "../../modules/network"

  vpc_cidr           = var.vpc_cidr
  public_subnet_cidr = var.public_subnet_cidr
  availability_zone  = var.availability_zone
}

module "security" {
  source = "../../modules/security"

  vpc_id             = module.network.vpc_id
  admin_cidrs        = var.admin_cidrs
  jenkins_agent_cidr = var.jenkins_agent_cidr
  jenkins_private_ip = var.jenkins.private_ip
}

module "compute" {
  source = "../../modules/compute"

  ami_id        = var.ami_id
  subnet_id     = module.network.public_subnet_id
  key_name      = var.key_name
  public_key    = file("${path.module}/crra-key.pub")
  jenkins_sg_id = module.security.jenkins_sg_id
  k3s_sg_id     = module.security.k3s_sg_id

  instance_profile_name = module.security.instance_profile_name
  jenkins               = var.jenkins
  k3s                   = var.k3s

  # Disposable host for the replacement demonstration; null when not in use.
  test_instance = var.test_instance
  test_sg_id    = module.security.test_sg_id
}

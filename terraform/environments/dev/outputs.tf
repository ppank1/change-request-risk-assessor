output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "vpc_id" {
  value = module.network.vpc_id
}

output "subnet_id" {
  value = module.network.public_subnet_id
}

output "jenkins_instance_id" {
  value = module.compute.jenkins_instance_id
}

output "k3s_instance_id" {
  value = module.compute.k3s_instance_id
}

output "jenkins_private_ip" {
  value = module.compute.jenkins_private_ip
}

output "k3s_private_ip" {
  value = module.compute.k3s_private_ip
}

output "jenkins_public_ip" {
  description = "Elastic IP; use this for the Jenkins root URL."
  value       = module.compute.jenkins_public_ip
}

output "k3s_public_ip" {
  description = "Elastic IP of the k3s host."
  value       = module.compute.k3s_public_ip
}

output "test_instance_id" {
  value = module.compute.test_instance_id
}

output "test_instance_public_ip" {
  value = module.compute.test_instance_public_ip
}

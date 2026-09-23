output "jenkins_instance_id" {
  value = aws_instance.jenkins.id
}

output "k3s_instance_id" {
  value = aws_instance.k3s.id
}

output "jenkins_private_ip" {
  value = aws_instance.jenkins.private_ip
}

output "k3s_private_ip" {
  value = aws_instance.k3s.private_ip
}

output "jenkins_public_ip" {
  description = "Elastic IP of the Jenkins host; stable across stop/start."
  value       = aws_eip.jenkins.public_ip
}

output "k3s_public_ip" {
  description = "Elastic IP of the k3s host; stable across stop/start."
  value       = aws_eip.k3s.public_ip
}

output "test_instance_id" {
  value = try(aws_instance.test[0].id, null)
}

output "test_instance_public_ip" {
  value = try(aws_instance.test[0].public_ip, null)
}

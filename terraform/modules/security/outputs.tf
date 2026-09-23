output "jenkins_sg_id" {
  value = aws_security_group.jenkins.id
}

output "k3s_sg_id" {
  value = aws_security_group.k3s.id
}

output "test_sg_id" {
  value = aws_security_group.test.id
}

output "instance_profile_name" {
  value = aws_iam_instance_profile.instance.name
}

output "jenkins_instance_profile_name" {
  description = "Least-privilege profile for the Jenkins host (terraform plan + ansible over SSM)."
  value       = aws_iam_instance_profile.jenkins.name
}

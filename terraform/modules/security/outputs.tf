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

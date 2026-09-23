# Compute layer: SSH key pair, the two hosts, their Elastic IPs, and an
# optional disposable instance used to demonstrate replacement.

resource "aws_key_pair" "this" {
  key_name   = var.key_name
  public_key = var.public_key

  # EC2 does not return public key material, so Terraform cannot compare it
  # after import and would force a destroy/recreate. The fingerprint recorded
  # in state proves the imported key is this key.
  lifecycle {
    ignore_changes = [public_key]
  }
}

locals {
  # Rendered once per host. Only attached where enabled; attaching user_data to
  # an existing instance is a rebuild, which is the point of immutability.
  user_data = {
    for name, host in { jenkins = var.jenkins, k3s = var.k3s } :
    name => templatefile("${path.module}/templates/user_data.sh.tftpl", {
      role     = name
      hostname = host.name
    })
  }
}

resource "aws_instance" "jenkins" {
  ami                    = var.ami_id
  instance_type          = var.jenkins.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.jenkins_sg_id]
  key_name               = aws_key_pair.this.key_name
  iam_instance_profile   = coalesce(var.jenkins_instance_profile_name, var.instance_profile_name)
  private_ip             = var.jenkins.private_ip
  ebs_optimized          = true
  user_data              = var.baseline_user_data ? local.user_data.jenkins : null

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size           = var.jenkins.root_volume_gb
    volume_type           = "gp3"
    iops                  = 3000
    throughput            = 125
    delete_on_termination = true
  }

  tags = { Name = var.jenkins.name, Role = "jenkins" }
}

resource "aws_instance" "k3s" {
  ami                    = var.ami_id
  instance_type          = var.k3s.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.k3s_sg_id]
  key_name               = aws_key_pair.this.key_name
  iam_instance_profile   = var.instance_profile_name
  private_ip             = var.k3s.private_ip
  ebs_optimized          = true
  user_data              = var.baseline_user_data ? local.user_data.k3s : null

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size           = var.k3s.root_volume_gb
    volume_type           = "gp3"
    iops                  = 3000
    throughput            = 125
    delete_on_termination = true
  }

  tags = { Name = var.k3s.name, Role = "k3s" }
}

# --- Elastic IPs ------------------------------------------------------------
# Stable public addresses that survive stop/start. Removes the failure mode
# where every configuration holding a public IP went stale after a restart.

resource "aws_eip" "jenkins" {
  domain = "vpc"
  tags   = { Name = "${var.jenkins.name}-eip" }
}

resource "aws_eip_association" "jenkins" {
  instance_id   = aws_instance.jenkins.id
  allocation_id = aws_eip.jenkins.id
}

resource "aws_eip" "k3s" {
  domain = "vpc"
  tags   = { Name = "${var.k3s.name}-eip" }
}

resource "aws_eip_association" "k3s" {
  instance_id   = aws_instance.k3s.id
  allocation_id = aws_eip.k3s.id
}

# --- Disposable test instance ----------------------------------------------
# Exists only while var.test_instance is set. Fully configured by user_data;
# any change to that script replaces the instance rather than editing it.

resource "aws_instance" "test" {
  count = var.test_instance == null ? 0 : 1

  ami                    = var.ami_id
  instance_type          = var.test_instance.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.test_sg_id]
  key_name               = aws_key_pair.this.key_name
  iam_instance_profile   = var.instance_profile_name
  ebs_optimized          = true

  user_data = templatefile("${path.module}/templates/user_data.sh.tftpl", {
    role     = "test"
    hostname = var.test_instance.name
  })
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size           = 10
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = { Name = var.test_instance.name }
}

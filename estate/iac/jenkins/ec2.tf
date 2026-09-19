data "aws_subnet" "app" {
  id = data.terraform_remote_state.network.outputs.app_subnet_ids[0]
}

resource "aws_instance" "jenkins" {
  ami                    = data.aws_ssm_parameter.al2_ami.value
  instance_type          = "t3.medium"
  subnet_id              = data.aws_subnet.app.id
  vpc_security_group_ids = [aws_security_group.jenkins.id]
  iam_instance_profile   = aws_iam_instance_profile.jenkins_instance.name
  user_data              = file("${path.module}/install.sh")

  # Inline, not aws_volume_attachment - that raced with cloud-init's ~15s
  # boot-time user-data run and mkfs hit "no such device" live.
  ebs_block_device {
    device_name = "/dev/sdf"
    volume_size = 30
    volume_type = "gp3"
    # No AWS Backup plan, no snapshot policy — PLANTED: AK-INF-06.
  }
}

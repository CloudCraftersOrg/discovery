data "aws_subnet" "app" {
  id = data.terraform_remote_state.network.outputs.app_subnet_ids[0]
}

resource "aws_instance" "runner" {
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = "t3.small"
  subnet_id              = data.aws_subnet.app.id
  vpc_security_group_ids = [aws_security_group.runner.id]
  iam_instance_profile   = aws_iam_instance_profile.runner.name

  user_data = templatefile("${path.module}/install.sh.tftpl", {
    runner_version            = var.runner_version
    github_org                = var.github_org
    github_repo               = "condor-pagos"
    runner_registration_token = var.runner_registration_token
  })
}

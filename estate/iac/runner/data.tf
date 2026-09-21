data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "condor-tfstate-${var.condor_account_id}"
    key    = "estate/network.tfstate"
    region = var.home_region
  }
}

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

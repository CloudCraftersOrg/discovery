data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "condor-tfstate-${var.condor_account_id}"
    key    = "estate/network.tfstate"
    region = var.home_region
  }
}

# Amazon Linux 2, not AL2023 like the rest of the estate — never revisited
# since this box was first stood up (PLANTED: AK-INF-05).
data "aws_ssm_parameter" "al2_ami" {
  name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
}

data "aws_iam_policy" "condor_sandbox_boundary" {
  name = "condor-sandbox-boundary"
}

resource "aws_security_group" "runner" {
  name        = "condor-gh-runner"
  description = "condor-gh-runner (egress only - polls GitHub, no inbound)"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id
}

resource "aws_vpc_security_group_egress_rule" "runner_all" {
  security_group_id = aws_security_group.runner.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

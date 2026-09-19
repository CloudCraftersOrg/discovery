resource "aws_security_group" "jenkins" {
  name        = "condor-jenkins"
  description = "condor-jenkins controller"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "jenkins_web" {
  security_group_id = aws_security_group.jenkins.id
  description       = "Jenkins web UI, in-VPC only"
  cidr_ipv4         = "10.20.0.0/16"
  from_port         = 8080
  to_port           = 8080
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "jenkins_all" {
  security_group_id = aws_security_group.jenkins.id
  cidr_ipv4          = "0.0.0.0/0"
  ip_protocol         = "-1"
}

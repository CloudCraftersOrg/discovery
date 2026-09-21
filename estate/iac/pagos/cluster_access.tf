# EKS's own cluster security group only allows inbound from its own
# members (the node group) by default - the runner needs an explicit rule
# to reach the private API endpoint at all (confirmed live: connection
# timeout without this).
resource "aws_vpc_security_group_ingress_rule" "cluster_api_from_runner" {
  security_group_id            = aws_eks_cluster.pagos.vpc_config[0].cluster_security_group_id
  referenced_security_group_id = data.terraform_remote_state.runner.outputs.runner_security_group_id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

data "aws_security_group" "jenkins" {
  filter {
    name   = "group-name"
    values = ["condor-jenkins"]
  }
}

resource "aws_vpc_security_group_ingress_rule" "cluster_api_from_jenkins" {
  security_group_id            = aws_eks_cluster.pagos.vpc_config[0].cluster_security_group_id
  referenced_security_group_id = data.aws_security_group.jenkins.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

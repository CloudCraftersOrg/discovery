resource "aws_eks_access_entry" "pagos_deploy" {
  cluster_name  = aws_eks_cluster.pagos.name
  principal_arn = aws_iam_role.pagos_deploy.arn
}

resource "aws_eks_access_policy_association" "pagos_deploy" {
  cluster_name  = aws_eks_cluster.pagos.name
  principal_arn = aws_iam_role.pagos_deploy.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"

  access_scope {
    type       = "namespace"
    namespaces = ["pagos"]
  }
}

# EKS API auth mode means IAM permissions (condor-jenkins-instance-role
# already has AdministratorAccess, AK-PIP-05) aren't enough on their own -
# a Kubernetes-level access entry is still required for kubectl/helm to work.
resource "aws_eks_access_entry" "jenkins" {
  cluster_name  = aws_eks_cluster.pagos.name
  principal_arn = "arn:aws:iam::337058058699:role/condor-jenkins-instance-role"
}

resource "aws_eks_access_policy_association" "jenkins" {
  cluster_name  = aws_eks_cluster.pagos.name
  principal_arn = "arn:aws:iam::337058058699:role/condor-jenkins-instance-role"
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"

  access_scope {
    type       = "namespace"
    namespaces = ["pagos"]
  }
}

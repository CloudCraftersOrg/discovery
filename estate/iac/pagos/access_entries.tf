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

# ---------------------------------------------------------------------------
# The discovery platform's collector, read-only, cluster-wide.
#
# WHY THE ESTATE GRANTS THIS RATHER THAN THE PLATFORM TAKING IT.
#
# EKS `API` auth mode means an IAM policy is not enough on its own: without a
# Kubernetes-level access entry, a principal with eks:DescribeCluster can see
# that the cluster EXISTS and nothing inside it. The `kubernetes` adapter reads
# in-cluster - namespaces, workloads, services, the things that make
# condor-pagos an application rather than a line item - and that read is the
# cluster owner's to grant.
#
# So it lives here, in the estate, next to the two entries that already exist
# for the same reason. A platform that could grant itself in-cluster access
# would not need asking, which is the property worth keeping.
#
# AmazonEKSViewPolicy, NOT Edit. The two entries above are Edit because they
# deploy; this one only looks. View maps to Kubernetes' built-in `view`
# ClusterRole, which CANNOT READ SECRETS - and that is the property that makes
# this safe to grant cluster-wide rather than namespace-scoped. A discovery
# tool that could read Secrets would be reading the client's credentials, which
# C1 forbids outright.
#
# Cluster scope rather than namespace: an assessment that only looks in `pagos`
# reports `pagos`, and the question the client is paying for is what is running
# EVERYWHERE. kube-system is where an unmanaged controller hides.
#
# Empty by default. An estate that has not been asked to be discovered grants
# nothing, and `terraform plan` shows exactly one entry appearing when it has.
resource "aws_eks_access_entry" "discovery_collector" {
  count = var.discovery_collector_role_arn == "" ? 0 : 1

  cluster_name  = aws_eks_cluster.pagos.name
  principal_arn = var.discovery_collector_role_arn
}

resource "aws_eks_access_policy_association" "discovery_collector" {
  count = var.discovery_collector_role_arn == "" ? 0 : 1

  cluster_name  = aws_eks_cluster.pagos.name
  principal_arn = var.discovery_collector_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.discovery_collector]
}

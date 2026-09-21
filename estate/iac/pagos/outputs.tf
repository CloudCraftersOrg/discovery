output "cluster_name" {
  value = aws_eks_cluster.pagos.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.pagos.endpoint
}

output "cluster_security_group_id" {
  value = aws_eks_cluster.pagos.vpc_config[0].cluster_security_group_id
}

output "ecr_repository_url" {
  value = aws_ecr_repository.pagos.repository_url
}

output "db_cluster_endpoint" {
  value = aws_rds_cluster.pagos.endpoint
}

output "pagos_deploy_role_arn" {
  value = aws_iam_role.pagos_deploy.arn
}

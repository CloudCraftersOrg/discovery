output "github_oidc_provider_arn" {
  value = data.aws_iam_openid_connect_provider.github_actions.arn
}

output "runner_instance_id" {
  value = aws_instance.runner.id
}

output "runner_security_group_id" {
  value = aws_security_group.runner.id
}

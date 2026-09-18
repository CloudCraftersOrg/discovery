output "condor_tfstate_bucket" {
  value = aws_s3_bucket.condor_tfstate.id
}

output "condor_bootstrap_role_arn" {
  value = aws_iam_role.condor_bootstrap.arn
}

output "condor_sandbox_boundary_arn" {
  value = aws_iam_policy.condor_sandbox_boundary.arn
}

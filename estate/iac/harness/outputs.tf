output "ledger_bucket_name" {
  value = aws_s3_bucket.harness_ledger.bucket
}

output "harness_uploader_role_arn" {
  value = aws_iam_role.harness_uploader.arn
}

output "tienda_approve_role_arn" {
  value = aws_iam_role.tienda_approve.arn
}

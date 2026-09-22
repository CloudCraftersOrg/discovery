# Untagged on purpose (PLANTED, evidence for a future finding): estate
# data that the not-yet-built platform collector roles must never read.
# No bucket policy denying them yet - those roles don't exist until
# Phase 2, same deferral condor-pagos-tf-ci used for infra.yml.
resource "aws_s3_bucket" "harness_ledger" {
  bucket = "condor-harness-ledger-${var.condor_account_id}"
}

resource "aws_s3_bucket_public_access_block" "harness_ledger" {
  bucket                  = aws_s3_bucket.harness_ledger.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "harness_ledger" {
  bucket = aws_s3_bucket.harness_ledger.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

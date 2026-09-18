# force_destroy on purpose (ADR-044): this whole repo is meant to be created
# and destroyed on demand, not run continuously. A state bucket that refuses
# to empty would turn "destroy the estate" into a manual cleanup step every
# single time.

resource "aws_s3_bucket" "condor_tfstate" {
  bucket        = "condor-tfstate-${var.condor_account_id}"
  force_destroy = true

  tags = {
    managed-by = "cloud-governance"
  }
}

resource "aws_s3_bucket_versioning" "condor_tfstate" {
  bucket = aws_s3_bucket.condor_tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "condor_tfstate" {
  bucket = aws_s3_bucket.condor_tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "condor_tfstate" {
  bucket = aws_s3_bucket.condor_tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

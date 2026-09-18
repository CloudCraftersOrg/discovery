# The bucket itself is P1-03's (estate/iac/baseline) — looked up here rather
# than duplicated so this layer doesn't own a resource another layer creates.
data "aws_s3_bucket" "condor_flowlogs" {
  bucket = "condor-flowlogs-${var.condor_account_id}"
}

data "aws_iam_policy_document" "condor_flowlogs_bucket" {
  statement {
    sid       = "AWSLogDeliveryWrite"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${data.aws_s3_bucket.condor_flowlogs.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.condor_account_id]
    }
  }

  statement {
    sid       = "AWSLogDeliveryAclCheck"
    effect    = "Allow"
    actions   = ["s3:GetBucketAcl"]
    resources = [data.aws_s3_bucket.condor_flowlogs.arn]

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
  }
}

resource "aws_s3_bucket_policy" "condor_flowlogs" {
  bucket = data.aws_s3_bucket.condor_flowlogs.id
  policy = data.aws_iam_policy_document.condor_flowlogs_bucket.json
}

resource "aws_flow_log" "condor" {
  vpc_id               = aws_vpc.condor.id
  traffic_type         = "ALL"
  log_destination_type = "s3"
  log_destination      = data.aws_s3_bucket.condor_flowlogs.arn

  destination_options {
    file_format        = "parquet"
    per_hour_partition = true
  }

  depends_on = [aws_s3_bucket_policy.condor_flowlogs]

  tags = {
    Name = "condor-flowlogs"
  }
}

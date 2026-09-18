resource "aws_s3_bucket" "condor_trail" {
  bucket        = "condor-trail-${var.condor_account_id}"
  force_destroy = true

  tags = {
    managed-by = "cloud-governance"
  }
}

data "aws_iam_policy_document" "condor_trail_bucket" {
  statement {
    sid       = "AWSCloudTrailAclCheck"
    effect    = "Allow"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.condor_trail.arn]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }

  statement {
    sid       = "AWSCloudTrailWrite"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.condor_trail.arn}/AWSLogs/${var.condor_account_id}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "condor_trail" {
  bucket = aws_s3_bucket.condor_trail.id
  policy = data.aws_iam_policy_document.condor_trail_bucket.json
}

resource "aws_cloudtrail" "condor" {
  name                          = "condor-trail"
  s3_bucket_name                = aws_s3_bucket.condor_trail.id
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true

  # Data events for S3 PutObject/DeleteObject on the tfstate bucket only —
  # P1-03 spec. The collector reads this bucket for drift/laptop-apply
  # evidence (task P1-13).
  advanced_event_selector {
    name = "condor-tfstate writes"

    field_selector {
      field  = "eventCategory"
      equals = ["Data"]
    }

    field_selector {
      field  = "resources.type"
      equals = ["AWS::S3::Object"]
    }

    field_selector {
      field       = "resources.ARN"
      starts_with = ["arn:aws:s3:::condor-tfstate-${var.condor_account_id}/"]
    }

    field_selector {
      field  = "eventName"
      equals = ["PutObject", "DeleteObject"]
    }
  }

  advanced_event_selector {
    name = "management events"

    field_selector {
      field  = "eventCategory"
      equals = ["Management"]
    }
  }

  depends_on = [aws_s3_bucket_policy.condor_trail]

  tags = {
    managed-by = "cloud-governance"
  }
}

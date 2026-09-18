resource "aws_s3_bucket" "condor_cur" {
  bucket        = "condor-cur-${var.condor_account_id}"
  force_destroy = true

  tags = {
    managed-by = "cloud-governance"
  }
}

data "aws_iam_policy_document" "condor_cur_bucket" {
  statement {
    sid    = "BillingWrite"
    effect = "Allow"
    actions = [
      "s3:GetBucketAcl",
      "s3:GetBucketPolicy",
      "s3:PutObject",
    ]
    resources = [
      aws_s3_bucket.condor_cur.arn,
      "${aws_s3_bucket.condor_cur.arn}/*",
    ]

    principals {
      type        = "Service"
      identifiers = ["billingreports.amazonaws.com", "bcm-data-exports.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.condor_account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "condor_cur" {
  bucket = aws_s3_bucket.condor_cur.id
  policy = data.aws_iam_policy_document.condor_cur_bucket.json
}

# CUR 2.0 via Data Exports. Billing APIs are us-east-1 only regardless of
# HOME_REGION — CUR2 lives outside the two-region split everything else here
# follows.
resource "aws_bcmdataexports_export" "condor_cur2" {
  export {
    name = "condor-cur2"

    data_query {
      query_statement = "SELECT * FROM COST_AND_USAGE_REPORT"

      table_configurations = {
        COST_AND_USAGE_REPORT = {
          TIME_GRANULARITY                      = "DAILY"
          INCLUDE_RESOURCES                     = "TRUE"
          INCLUDE_MANUAL_DISCOUNT_COMPATIBILITY = "FALSE"
          INCLUDE_SPLIT_COST_ALLOCATION_DATA    = "FALSE"
        }
      }
    }

    destination_configurations {
      s3_destination {
        s3_bucket = aws_s3_bucket.condor_cur.id
        s3_prefix = "condor-cur2"
        s3_region = var.home_region

        s3_output_configurations {
          overwrite   = "OVERWRITE_REPORT"
          format      = "PARQUET"
          compression = "PARQUET"
          output_type = "CUSTOM"
        }
      }
    }

    refresh_cadence {
      frequency = "SYNCHRONOUS"
    }
  }

  depends_on = [aws_s3_bucket_policy.condor_cur]
}

resource "aws_ce_cost_allocation_tag" "app" {
  tag_key = "app"
  status  = "Active"
}

resource "aws_ce_cost_allocation_tag" "managed_by" {
  tag_key = "managed-by"
  status  = "Active"
}

resource "aws_costoptimizationhub_enrollment_status" "condor" {
  include_member_accounts = false
}

resource "aws_computeoptimizer_enrollment_status" "condor" {
  status = "Active"
}

# VPCs attach to this in P1-04 — created here so it exists before any flow
# log tries to target it.
resource "aws_s3_bucket" "condor_flowlogs" {
  bucket        = "condor-flowlogs-${var.condor_account_id}"
  force_destroy = true

  tags = {
    managed-by = "cloud-governance"
  }
}

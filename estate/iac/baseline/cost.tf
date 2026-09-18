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
      # SELECT * is rejected (ValidationException on a real apply) - BCM Data
      # Exports requires an explicit column list. This one, not the full
      # 125-column dictionary: enough for cost attribution and grouping
      # (AK-GRP-10's managed-by tag, AK-BC-01's CUR reconciliation).
      query_statement = <<-SQL
        SELECT
          bill_bill_type,
          bill_billing_entity,
          bill_billing_period_end_date,
          bill_billing_period_start_date,
          bill_payer_account_id,
          bill_payer_account_name,
          identity_line_item_id,
          identity_time_interval,
          line_item_availability_zone,
          line_item_currency_code,
          line_item_legal_entity,
          line_item_line_item_description,
          line_item_line_item_type,
          line_item_net_unblended_cost,
          line_item_operation,
          line_item_product_code,
          line_item_resource_id,
          line_item_unblended_cost,
          line_item_unblended_rate,
          line_item_usage_account_id,
          line_item_usage_account_name,
          line_item_usage_amount,
          line_item_usage_end_date,
          line_item_usage_start_date,
          line_item_usage_type,
          pricing_currency,
          product_product_family,
          product_region_code,
          product_servicecode,
          resource_tags
        FROM COST_AND_USAGE_REPORT
      SQL

      table_configurations = {
        COST_AND_USAGE_REPORT = {
          TIME_GRANULARITY                      = "DAILY"
          INCLUDE_RESOURCES                     = "TRUE"
          INCLUDE_MANUAL_DISCOUNT_COMPATIBILITY = "FALSE"
          INCLUDE_SPLIT_COST_ALLOCATION_DATA    = "FALSE"
          # AWS auto-populates this to the account's primary billing view and
          # returns it on every read; leaving it unset here makes every
          # subsequent plan want to destroy and recreate the export.
          BILLING_VIEW_ARN = "arn:aws:billing::${var.condor_account_id}:billingview/primary"
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

# Cost allocation tag activation is a management-account-only operation
# (AccessDeniedException: "Linked account doesn't have access to cost
# allocation tags", confirmed on a real apply, 337058058699 is a member
# account) - CLAUDE.md's own stop condition for this exact case. See
# tasks/HANDOFF-P1-03.md.

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

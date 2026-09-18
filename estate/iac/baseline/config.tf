resource "aws_s3_bucket" "condor_config" {
  bucket        = "condor-config-${var.condor_account_id}"
  force_destroy = true

  tags = {
    managed-by = "cloud-governance"
  }
}

data "aws_iam_policy_document" "condor_config_bucket" {
  statement {
    sid       = "AWSConfigBucketPermissionsCheck"
    effect    = "Allow"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.condor_config.arn]

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
  }

  statement {
    sid       = "AWSConfigBucketDelivery"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.condor_config.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "condor_config" {
  bucket = aws_s3_bucket.condor_config.id
  policy = data.aws_iam_policy_document.condor_config_bucket.json
}

data "aws_iam_policy_document" "condor_config_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "condor_config" {
  name               = "condor-config-recorder"
  assume_role_policy = data.aws_iam_policy_document.condor_config_trust.json

  tags = {
    managed-by = "cloud-governance"
  }
}

resource "aws_iam_role_policy_attachment" "condor_config" {
  role       = aws_iam_role.condor_config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

module "config_home" {
  source          = "./modules/config-recorder"
  role_arn        = aws_iam_role.condor_config.arn
  delivery_bucket = aws_s3_bucket.condor_config.id
}

module "config_denied_region" {
  source          = "./modules/config-recorder"
  role_arn        = aws_iam_role.condor_config.arn
  delivery_bucket = aws_s3_bucket.condor_config.id

  providers = {
    aws = aws.denied_region
  }
}

resource "aws_config_configuration_aggregator" "condor" {
  name = "condor-aggregator"

  account_aggregation_source {
    account_ids = [var.condor_account_id]
    all_regions = true
  }
}

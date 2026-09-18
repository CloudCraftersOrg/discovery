# One recorder + delivery channel, parameterized so the root module can
# instantiate it once per region (HOME_REGION, DENIED_REGION) with the
# provider alias passed via the `providers` block at the call site.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

variable "role_arn" {
  type = string
}

variable "delivery_bucket" {
  type = string
}

resource "aws_config_configuration_recorder" "this" {
  name     = "condor-recorder"
  role_arn = var.role_arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = false
  }
}

resource "aws_config_delivery_channel" "this" {
  name           = "condor-delivery"
  s3_bucket_name = var.delivery_bucket

  depends_on = [aws_config_configuration_recorder.this]
}

resource "aws_config_configuration_recorder_status" "this" {
  name       = aws_config_configuration_recorder.this.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.this]
}

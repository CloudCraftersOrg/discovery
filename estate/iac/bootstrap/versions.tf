# Local state on purpose (see README.md): this layer creates the S3 bucket
# every later estate layer backends into, so it cannot backend into it itself
# on a first apply. Applied with the operator's own AIDiscoveryAccess
# profile, not with condor-bootstrap — this layer creates that role.

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.home_region
}

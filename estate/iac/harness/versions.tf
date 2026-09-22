# Applied as condor-bootstrap.

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket = "condor-tfstate-337058058699"
    key    = "harness/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.home_region
}

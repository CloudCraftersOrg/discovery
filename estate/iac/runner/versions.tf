# Applied as condor-bootstrap. Never shares a state file with Pagos -
# everything here is platform tooling for grouping purposes (task P1-07).

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
    key    = "runner/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.home_region
}

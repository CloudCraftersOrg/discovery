# Applied as condor-bootstrap. ADR-044: one VPC, one region — the only
# other region touched here is DENIED_REGION, for the canary parameter only.

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }

  backend "s3" {
    bucket = "condor-tfstate-337058058699"
    key    = "estate/network.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.home_region
}

provider "aws" {
  alias  = "denied_region"
  region = var.denied_region
}

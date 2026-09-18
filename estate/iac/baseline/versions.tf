# Applied as condor-bootstrap, backed into the state bucket P1-01 created.
# Two regions: HOME_REGION (everything) and DENIED_REGION (Config only, so
# the collector's coverage=access_denied finding in that region has
# something real to be denied against).

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
    key    = "estate/baseline.tfstate"
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

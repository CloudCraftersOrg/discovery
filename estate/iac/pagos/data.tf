data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "condor-tfstate-${var.condor_account_id}"
    key    = "estate/network.tfstate"
    region = var.home_region
  }
}

data "terraform_remote_state" "runner" {
  backend = "s3"
  config = {
    bucket = "condor-tfstate-${var.condor_account_id}"
    key    = "runner/terraform.tfstate"
    region = var.home_region
  }
}

variable "condor_account_id" {
  type = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.condor_account_id))
    error_message = "condor_account_id must be a 12-digit AWS account ID."
  }
}

variable "home_region" {
  type    = string
  default = "us-east-1"
}

variable "denied_region" {
  type    = string
  default = "sa-east-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

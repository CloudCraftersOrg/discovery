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

variable "github_org" {
  type    = string
  default = "CloudCraftersOrg"
}

# Oldest EKS version still in standard support, resolved live via
# `aws eks describe-cluster-versions` on 2026-09-19 (PLANTED: AK-INF-03).
variable "eks_version" {
  type    = string
  default = "1.34"
}

# condor-bootstrap itself - kubectl/helm run from the runner using its
# assumed-role session, not the raw AIDiscoveryAccess SSO role.
variable "operator_principal_arn" {
  type    = string
  default = "arn:aws:iam::337058058699:role/condor-bootstrap"
}

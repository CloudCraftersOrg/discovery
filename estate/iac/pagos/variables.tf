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

variable "discovery_collector_role_arn" {
  description = <<-EOT
    The discovery platform's collector role, granted read-only in-cluster
    access so its `kubernetes` adapter can see what runs here.

    Empty means no access entry at all: an estate that has not been asked to be
    discovered grants nothing, and enabling it is one line and one visible plan
    diff rather than a default somebody inherits.

    The role is per engagement - dp-<engagement>-collector, created by the
    platform's 30-collect layer - so the estate names it explicitly rather than
    pattern-matching. A wildcard here would grant every future engagement
    in-cluster access to this cluster.
  EOT
  type        = string
  default     = ""

  validation {
    condition = (var.discovery_collector_role_arn == "" ||
    can(regex("^arn:aws:iam::[0-9]{12}:role/.+$", var.discovery_collector_role_arn)))
    error_message = "An IAM role ARN, or empty to grant nothing."
  }
}

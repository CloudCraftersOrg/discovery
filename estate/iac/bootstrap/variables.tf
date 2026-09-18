variable "condor_account_id" {
  type        = string
  description = "The only account this whole repo may touch. Set by the operator."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.condor_account_id))
    error_message = "condor_account_id must be a 12-digit AWS account ID."
  }
}

variable "home_region" {
  type        = string
  description = "CLAUDE.md HOME_REGION — estate, platform, CUR, Cost Optimization Hub."
  default     = "us-east-1"
}

# The role AIDiscoveryAccess resolves to on the personal Sandbox account
# (CloudCraftersOrg/aws-access PR #38). Not a secret — an IAM role ARN, not a
# credential — but a variable rather than hardcoded so this stays portable if
# the SSO instance or account ever changes.
variable "operator_principal_arn" {
  type        = string
  description = "IAM role ARN condor-bootstrap trusts to assume it — the operator's own AIDiscoveryAccess session."
  default     = "arn:aws:iam::337058058699:role/aws-reserved/sso.amazonaws.com/us-west-2/AWSReservedSSO_AIDiscoveryAccess_ea884995ec425c40"
}

variable "monthly_budget_usd" {
  type        = string
  description = "Monthly budget for the whole PoC. Set by the operator."
}

variable "budget_notification_email" {
  type        = string
  description = "Where the 50/80/100% budget alerts go. Set by the operator."
}

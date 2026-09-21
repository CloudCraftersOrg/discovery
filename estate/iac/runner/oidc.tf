# Pre-existing in this account (created 2026-08-26, unrelated to Condor) -
# AWS allows only one OIDC provider per issuer URL per account, and this
# one already has the right client_id, so this set references it rather
# than fighting over ownership of shared, account-wide infrastructure.
data "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
}

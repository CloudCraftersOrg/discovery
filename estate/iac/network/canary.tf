# AK-COV-01: the collector must be denied here. Never a VPC element —
# unaffected by ADR-044.
resource "aws_ssm_parameter" "canary" {
  provider = aws.denied_region

  name  = "/condor/canary"
  type  = "String"
  value = "denied-region"

  tags = {
    managed-by = "cloud-governance"
  }
}

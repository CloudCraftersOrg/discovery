# iac

Terraform for the estate — condor-bootstrap only, one state bucket, never shares state with platform/. Bootstrap (identities/state/budget), baseline (account telemetry) and network (the shared VPC) live here as separate Terraform layers, applied in that order.

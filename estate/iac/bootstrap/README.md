# bootstrap

One-time bootstrap Terraform (task P1-01): the condor-tfstate state bucket, the condor-bootstrap role and its scoped policy, the condor-sandbox-boundary permissions boundary, and the monthly budget. Applied with the operator's own AIDiscoveryAccess profile, not with condor-bootstrap itself — this layer creates that role, so nothing can assume it yet.

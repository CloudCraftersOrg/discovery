# ADR-041: Estate link — security groups within one VPC, not VPC peering

## Status

Accepted. Supersedes this ADR's own original content (P2-03's task text described VPC peering plus a Route 53 Resolver endpoint pair — written before ADR-044 merged the estate and discovery platform into one VPC).

## Context

Collectors (in the platform's subnets) need to reach two things inside the estate: the Pagos EKS private API and Jenkins. Before ADR-044, `condor-estate` and `dp-discovery` were separate VPCs, so this required VPC peering (routes scoped to just the estate `app` subnets) plus a Route 53 Resolver outbound endpoint in the platform VPC and an inbound endpoint in the estate VPC to resolve the EKS private endpoint's hostname across the peering connection.

ADR-044 removed the second VPC. The platform's subnets now live inside `condor-vpc` itself, in the space reserved at `10.20.128.0/18`.

## Decision

No VPC peering, no cross-VPC private-zone association, no Resolver endpoint pair. `condor.internal` (P1-04) is already associated with `condor-vpc`; a Lambda in the platform's `collector` subnet resolves `jenkins.condor.internal` and the EKS private endpoint's hostname through the VPC's own built-in resolver, the same as everything else in the VPC. The only remaining work (task P2-03) is security-group rules: EKS cluster SG allows 443 from `dp-collector`'s CIDRs, `condor-jenkins` SG allows 8080 from the same — narrowing what P1-11's own broader `10.20.0.0/16` rule already permits.

## Consequences

- P2-03 shrinks from a dedicated multi-resource task to two security-group rules and a test Lambda. Its cost limit drops from $0.30/hr to $0.02/hr — the Resolver endpoint pair this ADR no longer needs was most of that cost.
- P3-04's self-exclusion view no longer lists "the peering connection" or Resolver endpoints among excluded resources — there's nothing there to exclude. It lists the platform's subnets/security-groups within `condor-vpc` instead, since there's no separate VPC to exclude wholesale anymore.
- Same-VPC also means SG-rule violations are the *only* isolation mechanism left between platform and estate (no VPC boundary as a second layer) — acceptable here since the estate is a fixture with no real data, but worth naming as a real trade this ADR makes, not an accident.

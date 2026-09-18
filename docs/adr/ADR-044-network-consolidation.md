# ADR-044: One VPC, one region

## Status

Accepted.

## Context

The original design spanned three VPCs across two regions: `condor-estate` and `dp-discovery` in `HOME_REGION` (us-east-1), `condor-promo` isolated in a `SECOND_REGION` (us-west-2), connected by VPC peering plus a cross-VPC Route 53 Resolver endpoint pair. This is a PoC meant to be created and destroyed on demand, not run continuously — the multi-VPC/multi-region shape adds teardown surface (peering connection, Resolver endpoints, a second region's worth of NAT/flow-logs/Config) without adding anything the estate or the platform actually needs to demonstrate.

## Decision

Everything lives in one VPC, `condor-vpc`, `10.20.0.0/16`, in `HOME_REGION`. `condor-promo`'s three planted findings (AK-COV-04, AK-INF-07, AK-PIP-08) move into an isolated subnet of that VPC (no `0.0.0.0/0` route) instead of a second-region VPC — they keep the "forgotten, isolated" characteristic; they lose the "wrong region" one. The `DENIED_REGION` canary (`sa-east-1`) is unaffected — it was never a VPC element, only an IAM region-lock negative test.

VPC peering, the Resolver inbound/outbound endpoint pair, and the cross-VPC private-zone association are eliminated entirely: same-VPC subnets share `condor.internal` and route to each other via security groups, once the platform's subnets join this same VPC later.

`10.20.128.0/18` is reserved, unused, for the platform's collector/data/firewall subnets when platform work starts. The estate's `app` (`10.20.10.0/24`, `.11.0/24`) and `data` (`10.20.20.0/24`, `.21.0/24`) subnets keep their original addressing, so P1-11's existing Jenkins security-group rule (scoped to `10.20.0.0/16`) needs no edit and already covers collector access once collectors join the block.

## Consequences

- Fewer things to tear down: one NAT gateway instead of up to two, no peering connection, no Resolver endpoints.
- `SECOND_REGION` is removed from `CLAUDE.md`'s environment table. `P1-03`'s Config recorder drops from three regions to two.
- The one thing this trades away: AK-COV-04/07/08 now prove "discovered something in an unexpected subnet" rather than "discovered something in an unexpected region." Revisit if that distinction turns out to matter to the eventual AWS Transform handoff.
- `AIDiscoveryAccess` (the personal-estate SSO permission set backing this build) still grants `us-west-2` — now dead weight, tracked as a follow-up cleanup in `CloudCraftersOrg/aws-access`, not blocking this repo.

# ADR-040: Egress invariant — IGW for NAT, nothing else routes to it

## Status

Accepted. Corrects an earlier "no internet gateway" statement.

## Context

NAT gateways require an internet gateway attached to the VPC — there's no way to give private subnets outbound internet access without one. An earlier design statement said the platform's VPC would have no IGW at all, which turns out to be impossible given the platform's collectors need to reach GitHub (task P2-02).

## Decision

The VPC has one internet gateway. Only the public/NAT subnet tier's route table points at it. No `collector`, `data`, or estate workload subnet has a route to the IGW, directly or otherwise — every byte of collector egress passes through Network Firewall (task P2-02) with a domain allowlist (`github.com`, `api.github.com`, `codeload.github.com`, `objects.githubusercontent.com`, `updates.jenkins.io`, `www.jenkins.io`, plus any AWS domain lacking a VPC endpoint, recorded per-domain in an ADR at the time P2-01 needs it).

## Consequences

- "No internet gateway" is corrected to "an IGW exists, but no workload subnet can reach it directly" — the invariant that actually matters (no uncontrolled egress) is preserved; the literal absence of an IGW was never the point.
- `terraform plan` for `platform/terraform` should always show zero routes from `collector`/`data` route tables to the IGW — worth a `check` block (as P2-01 already specifies) rather than relying on manual review to catch a regression here.

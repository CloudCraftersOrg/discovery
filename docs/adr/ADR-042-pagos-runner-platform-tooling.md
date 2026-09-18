# ADR-042: The Pagos self-hosted runner is shared platform tooling

## Status

Accepted.

## Context

GitHub-hosted runners cannot reach the private EKS API endpoint Pagos deploys to (ADR-041/ADR-044: no public path exists, by design — CLAUDE.md #4). Pagos therefore deploys through a self-hosted runner (`condor-gh-runner`, task P1-07) living inside the estate VPC, not a GitHub-hosted one.

Grouping (task P4-04) needs to decide what entity a resource belongs to. `condor-gh-runner` is infrastructure Pagos's pipeline depends on, but it isn't Pagos's own application infrastructure — it's generic CI capacity that happens to currently serve one app.

## Decision

`condor-gh-runner` is classified `platform_tooling` (same `entity_type` as `condor-jenkins`), not folded into the `pagos` application entity — grouping evidence: `AK-GRP-09`, via `ssm_inventory`/`config`.

## Consequences

- The dependency `pagos depends_on condor-gh-runner` (or the pipeline-link equivalent) still needs to be captured — classifying the runner as `platform_tooling` doesn't mean the relationship disappears, only that the runner isn't double-counted as part of Pagos's own footprint (cost, rightsizing findings, etc.).
- If a second app ever used the same runner, this classification is already correct for that case — the alternative (grouping it under Pagos) would have needed revisiting the moment a second consumer showed up.

# ADR-039: A private ECR repo exists, for the dbt image only

## Status

Accepted. Corrects an earlier "no ECR" statement.

## Context

The dbt Lambda (ADR-038) runs from a container image, not a zip package — dbt-athena's dependency footprint doesn't fit Lambda's zip size limit. Container-image Lambdas require the image to live in ECR.

## Decision

One private ECR repository, `dp-dbt`, holding only the dbt Lambda's container image. No other workload in this PoC uses a container-image Lambda or otherwise needs its own ECR repo.

## Consequences

- "No ECR for workloads" (an earlier, broader statement) is corrected to "no ECR for workloads *except* the one image that has to be one" — the exception is narrow and named, not a general opening.
- `condor-inventario`'s own ECR repo (`estate/apps/condor-inventario`, task P1-08) is a separate, unrelated repo in the *estate*, not the platform — it's deliberately misconfigured (mutable tags, scanning off, AK-PIP-09) as a planted finding, not a consequence of this decision.

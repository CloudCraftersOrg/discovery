# ADR-038: dbt-athena for transforms, Aurora for the canonical model

## Status

Accepted.

## Context

Raw collector output lands in `dp-raw` as JSON Lines. Two different kinds of downstream work need it: bulk analytical transforms (grouping, dependency derivation, dashboards) and the canonical model's identity resolution and bitemporal assertions (`docs/contracts/canonical-model.md`), which needs row-level upsert and point lookups — a poor fit for a lakehouse table format.

## Decision

- **Transforms**: `dbt-athena`, running against Iceberg tables in `dp-lake`, from a Lambda container image in the private ECR repo `dp-dbt` (ADR-039).
- **Canonical model**: Aurora PostgreSQL Serverless v2, accessed through the RDS Data API (no persistent connection pool needed from Lambda) — `platform/db/migrations/0001_init.sql`.
- Canonical tables are exported back to Iceberg (`dp-lake`) for the dashboards (Amazon Quick, task P4-11) to read — dashboards query the lake, not Aurora directly.

## Consequences

- Two storage engines to operate instead of one, but each is doing the job it's actually good at: Iceberg/Athena for scan-heavy analytical transforms, Postgres for point lookups and upserts during identity resolution.
- The export-back-to-Iceberg step is an extra pipeline stage (P4-01) and a place staleness can creep in between an Aurora write and the next dashboard refresh — acceptable for a PoC's refresh cadence, would need revisiting for a production SLA.

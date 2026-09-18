# Canonical model

The schema every collector's output eventually resolves into, in Aurora PostgreSQL Serverless v2 (ADR-038), accessed through the RDS Data API. Full DDL: `platform/db/migrations/0001_init.sql`.

## Tables

- **`run`** — one row per platform run. `status`: `running`, `succeeded`, `failed`.
- **`entity`** — the resolved thing (a resource, an application, a pipeline, ...). `entity_type` enum: `resource`, `application`, `pipeline`, `repository`, `identity`, `image`, `platform_tooling`, `governance`, `shared_infrastructure`. Unique on `(entity_type, natural_key)`.
- **`identity_link`** — the raw keys (ARN, instance ID, IP, ...) that resolve to one `entity`. `key_type` enum matches the confidence ladder's signal types; `tier`/`confidence` come from `source_precedence`.
- **`assertion`** — bitemporal: `observed_at`/`recorded_at` are when the fact was true in AWS vs. when the platform learned it; `valid_from`/`valid_to` track supersession when a later assertion on the same `(entity_id, attribute)` arrives. `valid_to IS NULL` means current.
- **`relation`** — edges between entities. `relation_type` enum: `member_of`, `depends_on`, `deploys_to`, `built_from`, `runs_image`, `operational_automation`, `managed_by_iac`.
- **`evidence`** — points a derived row (`derived_table`/`derived_id`) back at the exact raw record (`raw_s3_uri`/`raw_line`/`payload_sha256`) that produced it. This is what makes every finding traceable to a specific collector output.
- **`source_precedence`** — the confidence ladder from `CLAUDE.md` section 7, seeded once by the migration. Grouping and identity resolution read this table rather than hardcoding the ladder a second time.
- **`adjudication`** — where a conflict between candidate groupings/identities gets resolved (automatically or by a human), and the record of that decision.
- **`validation_state`** — one row per entity that's gone through the validation workbook (P5-01/P5-02). `status` enum: `issued`, `confirmed`, `corrected`, `reassigned`, `partial`, `no_response`, `escalated`, `signed_off`.
- **`finding`** — the thing that reaches a dashboard or the business case. Every value column (`value_usd`, `band_low`, `band_expected`, `band_high`, `band_assumption`, `realization_lag_days`, `evidence_ids`) is `NOT NULL` — a finding without a quantified, evidenced value doesn't belong in this table (CLAUDE.md section 7: "No finding reaches a dashboard or the business case without all three").

## Why bitemporal on `assertion` only

`relation` also carries `valid_from`/`valid_to` for the same supersession reason, but only `assertion` needs the observed/recorded split — a relation (e.g. `tienda depends_on pagos`) doesn't have a meaningfully different "when it was true" from "when we learned it" the way a resource's tag value or instance type does, since relations are themselves derived from assertions, not observed directly.

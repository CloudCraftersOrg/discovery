# ADR-037: Single account, single environment

## Status

Accepted.

## Context

A real client estate spans multiple AWS accounts and environments (dev/staging/prod). This is a PoC demonstrating discovery and modernization assessment, not a multi-account landing zone exercise.

## Decision

Everything — the fictional Mercado Cóndor estate and the discovery platform that scans it — lives in one AWS account, `$CONDOR_ACCOUNT_ID`, with no dev/staging/prod split. `CLAUDE.md` section 1 states this directly: "Two things live in one AWS account."

## Consequences

- Simpler to build and, per ADR-044, simpler to destroy and recreate on demand — no cross-account IAM, no account-vending, no environment promotion pipeline to fake.
- The PoC cannot demonstrate cross-account discovery, which a real engagement often needs. Out of scope here; the demo's job is proving the discovery and grouping model works, not proving multi-account scale.

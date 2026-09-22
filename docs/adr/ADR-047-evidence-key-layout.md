# ADR-046: Evidence key layout carries engagement and account

## Status

Accepted.

## Context

`CLAUDE.md` section 7 fixes the raw key layout as
`raw/domain=/source=/run_id=/region=/part-<n>.jsonl.gz`. That is correct for this
repository: ADR-037 puts the estate and the platform in one account, so account
is a constant and engagement is not a concept.

It stops being correct the moment the platform is deployed at a client. The
product this PoC exists to prove
([`CloudCraftersOrg/ai-discovery-tool`](https://github.com/CloudCraftersOrg/ai-discovery-tool),
`SPEC.md` departures 1 and 10) reads N accounts from one platform account, and
runs several engagements from it. Under the current layout, "what did we find in
account X" has no partition to prune on and scans every record in the run. At the
sizes that specification targets — 20 accounts, 50 000 resources, ~10 GB of
evidence per run — that is the single largest Athena line in the platform, and it
is paid on every query rather than once.

The envelope already carries `account_id` as a required field, so the information
is present on every record. It is only the *key* that discards it.

`P3-02` and `P3-03` are both `todo`. There is no evidence in the old shape, and no
staging model reading it.

## Decision

The layout becomes:

```
raw/engagement=<slug>/run_id=<ulid>/domain=<infra|apps|pipelines>/source=<collector>/account=<account_id>/region=<region>/part-<n>.jsonl.gz
```

`engagement` is `condor` here and a client slug elsewhere. `account` is the
account the record was collected *from*, which at a client is not the account the
platform runs in.

Ordering is by how queries actually filter. Engagement and run are in almost every
predicate, so they prune first; account and region sit deep, because by then the
scan is already reduced to one collector's output for one run.

Two consequences follow and are made in the same change, because a partition that
only some of the pipeline knows about is worse than none:

- `P3-03`'s `raw_records` external table projects all six partitions, in that
  order. Projection, not a crawler: the values are enumerable from the run ledger,
  so a crawler would be a scheduled cost and a drift source for information
  already known.
- `P3-02`'s deduplication and idempotency keys gain `account_id`. Not every
  `resource_id` is an ARN — instance IDs, bucket names and synthesized IDs can
  repeat across accounts — and collapsing two accounts' records into one row is a
  silent loss rather than an error.

## Consequences

- Two partitions with cardinality 1 in this repository. They cost one extra path
  segment each and buy nothing here, which is the point: the PoC writes evidence
  in the shape the product reads, so the staging models and the contract tests are
  the same code in both deployments.
- ADR-037 is unaffected. This does not make the PoC multi-account; it makes its
  output layout forward-compatible with a platform that is.
- `CLAUDE.md` section 7 is edited, which is rare and deliberate. The envelope
  schema is not: `account_id` was already required, so no record changes shape and
  `envelope_version` stays `"1"`.
- Done now, this is three edits to `todo` tasks. Done after `P3-02` runs, it is a
  re-collection or a rewrite of immutable evidence, and Object Lock (`P3-05`) makes
  the second of those expensive on purpose.

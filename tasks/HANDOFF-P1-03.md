# HANDOFF-P1-03 · Amazon Quick subscription

Not created by Terraform — Quick account subscriptions are a one-time,
per-account console action with no clean `terraform destroy` path, which
would work against ADR-044's create/destroy-on-demand design. Do this once,
by hand, only when Phase 4 (`P4-11` dashboards) actually needs it — not now.

**Steps, when that time comes:**

1. AWS Console → Amazon QuickSight → Sign up.
2. Edition: **Enterprise** (required for the CID dashboards, task `P2-06`).
3. Authentication: IAM Identity Center (matches how `AIDiscoveryAccess` already
   signs in — do not create a separate QuickSight-only identity).
4. Account name: `condor-discovery`. Notification email: the operator's own.
5. Region: `us-east-1` (`HOME_REGION`) — QuickSight is regional and every
   dashboard task assumes this region.
6. Do **not** enable the QuickSight sample data / sample dashboards option —
   keeps the account free of anything that could be mistaken for a real
   finding.
7. Grant QuickSight IAM access to the `dp-raw`/`dp-lake`/`dp-athena-results`
   buckets and the Athena workgroup when `P2-06`/`P4-11` actually run — not
   before, since those don't exist yet either.

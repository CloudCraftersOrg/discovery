# HANDOFF-P1-03

## Cost allocation tag activation — management-account-only

`terraform apply` failed on `aws_ce_cost_allocation_tag.app`/`.managed_by` with `AccessDeniedException: Linked account doesn't have access to cost allocation tags`. This account (`337058058699`) is a member account of the CloudCraftersOrg organization; cost allocation tag activation is only callable from the management account (`905081188087`, `santiacmaestre-cloudlab`), regardless of what IAM permissions the caller holds in the member account. `CLAUDE.md`'s own stop condition covers this exactly — not worked around, removed from `cost.tf`.

**Steps, for whoever holds access to the management account:**

1. Sign in to `905081188087` (or use a permission set that reaches it — `AIGovernanceAdminAccess` includes Organizations read/write but not `ce:*`; check before assuming it covers this).
2. Cost allocation tags are managed from the *linked* account's own Billing console even when activated by the management account — the actual toggle is: Billing and Cost Management → Cost allocation tags, filtered to account `337058058699`, activate `app` and `managed-by`.
3. Alternatively, `aws ce update-cost-allocation-tags-status --cost-allocation-tags-status TagKey=app,Status=Active TagKey=managed-by,Status=Active` from a management-account session with `ce:UpdateCostAllocationTagsStatus` — confirm whether this needs to run scoped to the linked account or account-wide; the CLI docs weren't conclusive from here.

Until this happens, `AK-GRP-10`'s `managed-by` tag-based grouping evidence still works (Config/tagging collectors read the tag value directly, independent of cost-allocation-tag activation) — only CUR-based cost attribution by these two tags is blocked.

## Amazon Quick subscription

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

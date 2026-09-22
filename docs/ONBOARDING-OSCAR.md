# Onboarding — Oscar, platform infra

**Repo: `CloudCraftersOrg/ai-discovery-tool`, not this one.** Everything
below was originally scoped against `discovery`'s own `platform/`
scaffolding and `tasks/P2-01`/`P2-04`/`P2-06`/`P3-01`/`P3-03`/`P4-01`/
`P4-11`/`P5-02` — that track is superseded. Alejandro built a full,
general-purpose (not Condor-specific) version of this platform solo, in
`ai-discovery-tool`, in about 24 hours. Read this doc, then go work there.

`discovery` (this repo) is now a **reference**, not where you build: its
`docs/contracts/`, `answer-key/answer-key.yaml`, and `docs/ARCHITECTURE.md`
describe the Condor estate that `ai-discovery-tool` will run its first real
collection against (`ENGAGEMENT=condor`).

## Start here, in `ai-discovery-tool`

1. `README.md`, then `SPEC.md` §4 (deployment model), §5 (Terraform
   structure), §6 (network), §8 (data), §9 (security) — those five cover
   almost everything your original eight tasks touched.
2. `make check` locally (`fmt-check`, `validate`, offline tests, `policy`
   — Checkov) — no AWS credentials needed, and it's what CI runs on every
   PR.
3. `runbook/first-run.md` — the two things only a human can do before
   anything applies: set the `ENGAGEMENT` repo variable, upload
   engagement-specific tfvars (not committed — they carry account IDs and
   ARNs, kept out of git on purpose).
4. Skim recent `git log` on `main` — nearly every commit past the initial
   build is Alejandro finding and fixing a real bug on first contact with
   live AWS (Aurora's minor-version pin, a `10-network` layer that could
   never apply, IAM rejecting a wildcard in the action's service half, CI's
   apply role not trusting its own environment). That's the actual shape of
   the work left: **the code for all nine layers exists and validates;
   very little of it has been proven against a real account.**

## Where your eight tasks actually live now

| Your original task | What it covered | Where it lives in `ai-discovery-tool` |
|---|---|---|
| `P2-01` (network + storage base) | VPC, KMS, S3, DynamoDB | `terraform/10-network` + `terraform/20-data` — **both already built**: S3 `lake`/`athena_results` with lifecycle rules, Glue catalog, Athena workgroup, DynamoDB `run_ledger` |
| `P2-04` (collector identities) | `dp-collector` IAM role, EKS access, GitHub App | `terraform/30-collect/iam.tf` — **already built**, and broader than the original plan: AWS-managed `SecurityAudit` + `ViewOnlyAccess` plus an explicit `NeverWriteToAnEstate` deny list as defense in depth |
| `P2-06` (CID dashboards, License Manager, Well-Architected) | Deploy-not-build AWS services | **No clear home yet.** Not in any of the nine layers as far as I can find. Worth raising directly — it may be intentionally out of v1 scope (these are account-local AWS tools, and this product's whole model is reading *other* accounts through one granted role, which may be why it didn't carry over), or it may just not be built yet. Don't assume either way — ask Alejandro |
| `P3-01` (orchestration) | Step Functions, EventBridge | `terraform/30-collect/statemachine.tf` (the collection fan-out, already built — Distributed Map over accounts × regions × collectors) and `terraform/40-process/statemachine.tf` (the process pipeline). SPEC §7.3–7.4 describes both in more depth than the original task did — read it, the run model changed: **triggered, not scheduled**, four named runs (`probe`, `baseline`, `window`, `refresh`) instead of cron cadences |
| `P3-03` (lakehouse tables) | Glue, Athena, Iceberg | `terraform/20-data/main.tf` — Glue database and Athena workgroup exist. Whether the Iceberg table *schemas* (`stg_records`, `coverage`, `canonical_entity`, etc.) are actually created yet needs checking — I didn't find table-creation resources in what I read, only the database/workgroup shell |
| `P4-01` (canonical store, dbt) | Aurora, migrations, dbt image | `terraform/20-data/aurora.tf` (Aurora PostgreSQL Serverless v2, **just fixed** — the version pin bug was real, see `git log`) + `terraform/40-process/main.tf` (dbt Lambda, snapshot Lambda, judgment-layer Lambda — all three already built) |
| `P4-11` (dashboards) | QuickSight as code | Two different things exist and neither is clearly QuickSight yet: `terraform/60-console` is a **full custom web app** (Cognito, CloudFront, WAF) — the "Site" and "Console" product surfaces from SPEC §14, a different design than the original QuickSight plan. SPEC's own open question **Q5** asks whether Terraform should own QuickSight assets at all, or whether it's a human-authored, human-imported thing. This is unresolved — don't build QuickSight Terraform speculatively |
| `P5-02` (validation orchestration) | Workbook outbox/inbox | `terraform/50-present` — delivery bucket with presigned in/out access, already built |

## The real state of things

Per `README.md`'s own status note (check it's not stale before trusting
it): *"The nine layers, the client grant, the CI/CD and the app exist and
validate. None of it has been applied to an AWS account."* That's slightly
behind reality already — a recent commit shows `20-data` got through S3,
Glue and Athena on a real apply before hitting the Aurora bug, now fixed.
**Your job is mostly to continue that: apply layers in order, against the
real sandbox account, and fix what breaks on first contact** — the same
shape as every one of Alejandro's recent commits, not a from-scratch build.

**The AWS sandbox account is 337058058699, `us-east-1`** — the same
account that hosts the whole Condor estate from `discovery`. Two real
consequences: be careful never to touch estate resources with platform
credentials (there's an IAM deny for this, but don't rely on it), and
expect the estate's own resource footprint to be visible alongside
whatever you apply — don't mistake an estate resource for something you
created.

## Rules that carry over unchanged

Everything from the original CLAUDE.md-derived list still applies, just
against `ai-discovery-tool`'s own layers instead of `platform/`:

- Least privilege, no wildcards beyond what a task explicitly names.
- The collector role is read-only, full stop — any write API showing up
  there is a defect, not a feature (this is now an actual IAM Deny in
  `30-collect/iam.tf`, not just a convention).
- Never fix a planted estate defect "for security" if your work brings you
  into contact with Condor data (e.g. testing a `20-data` query against
  real collected evidence).
- Never sleep-loop waiting for AWS data — `discovery`'s own
  `estate/verify/check_ready.py` is still the reference pattern for a
  `wait`-gated check.

## Definition of done

`make check` passes (fmt, validate, offline tests, policy). Terraform plan
output and any live-apply findings go in the PR, matching the detail level
of Alejandro's own commit messages — they explain the real failure and why
the fix is correct, not just what changed. CI enforces PR-then-merge with
required-reviewer approval on the apply role's trust policy itself, so
there's no way to approve your own apply by editing the workflow file in
the same PR.

## Coordination

**Talk to Alejandro before touching anything.** He built all nine layers
solo in under 24 hours and has context on design decisions (like the P2-06
gap above, or the QuickSight-vs-console open question) that isn't fully
written down yet. Don't duplicate or contradict work he's mid-thought on —
confirm what he's already planning to pick up next before claiming a
layer.

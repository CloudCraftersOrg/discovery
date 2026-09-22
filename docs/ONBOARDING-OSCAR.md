# Onboarding — Oscar, Platform Services infra

Scope: the "Platform services" box (data stores, orchestration, analytics,
access/AWS-insight) — regional, outside `condor-vpc`. Eight tasks:
`P2-01`, `P2-04`, `P2-06`, `P3-01`, `P3-03`, `P4-01`, `P4-11`, `P5-02`.

Everything here is Phase 2+ (the discovery platform itself), not the
Condor estate. **Do not touch anything under `estate/`** — see the
"commonly get wrong" list below, it's not optional.

## Before you write any Terraform

1. Read `CLAUDE.md` in full — it's short, and sections 3–9 are the actual
   rules this whole repo runs on, not background.
2. Read `docs/adr/ADR-044-network-consolidation.md` and
   `ADR-045-bootstrap-identity.md` first. They already answer questions
   you'll otherwise re-derive: there is one VPC (`condor-vpc`), not two —
   the platform gets its own subnets inside it, not a peered VPC — and
   `dp-deployer` (your apply identity, parallel to the estate's
   `condor-bootstrap`) doesn't exist yet. Building it is implicitly your
   first real step, before `P2-01` can apply.
3. Confirm what's actually done vs. still `todo` in `tasks/STATUS.md`
   before starting each task — it's the single source of truth, not this
   doc, which will drift.
4. `platform/` already has real content: `platform/db/migrations/0001_init.sql`
   and its test (from `P2-05`, done) — the canonical Postgres schema your
   later tasks (`P4-01`) build on. Skim it before `P3-03`/`P4-01` so your
   Iceberg table schemas and Aurora migrations don't diverge from it.

## The eight tasks, in the order their dependencies force

| Order | Task | What | Depends on |
|---|---|---|---|
| 1 | `P2-01` | VPC `dp-discovery`... no — **one VPC**: platform subnets (`collector`, `data`, `firewall`, `nat`) inside `condor-vpc`. KMS keys, `dp-raw`/`dp-lake`/`dp-athena-results` S3, `dp-run-ledger`/`dp-checkpoints` DynamoDB. | `P1-01`, `P1-04` (done) |
| 2 | `P2-04` | IAM role `dp-collector`, EKS access entry, GitHub App `dp-discovery-reader`, `dp/jenkins/reader` token | `P2-01`, `P1-07`, `P1-11`, `P1-05` (done) |
| 3 | `P2-06` | Deploy-not-build: CID dashboards, License Manager configs, Well-Architected workload | `P1-03`, `P1-09` (done) |
| 4 | `P3-01` | Step Functions `dp-sfn-ingest`, EventBridge schedules, the CUR-delivery trigger | `P2-17` (blocked on the whole collector set — see coordination note) |
| 5 | `P3-03` | Glue database `dp_lake`, Iceberg tables, Athena workgroup `dp-analytics` | `P2-05` (done), `P2-01` |
| 6 | `P4-01` | Aurora Serverless v2 `dp-canonical`, `dp-migrate` Lambda, the dbt image, `dp-sfn-resolve-enrich` | `P3-02`, `P2-05` |
| 7 | `P4-11` | QuickSight dashboards as code, six of them | `P4-09`, `P3-06` |
| 8 | `P5-02` | Validation workbook orchestration (outbox/inbox in `dp-lake`, Step Functions, escalation Lambda) | `P5-01` |

**`P2-01` and `P2-04` are the two that block the most other people.**
`P2-04` specifically is what Santiago's Jenkins collector (`P2-15`) needs
before he can test against live Jenkins — his collector reads a token from
`dp/jenkins/reader`, which your task creates. Tell him when it lands.

`P3-01`, `P4-01`, `P4-11` and `P5-02` all sit late in their chains and
depend on work outside this box (`P2-17`, `P3-02`, `P4-09`, `P3-06`,
`P5-01`) — you'll be blocked waiting on other streams for those, not on
yourself. `P2-01`, `P2-04`, `P2-06` and `P3-03` are the ones you can start
and finish without waiting on anyone.

## Rules that are easy to break by accident

From `CLAUDE.md` §5 and §9 — these aren't style preferences, several have
acceptance tests that fail if you break them:

- **Every platform resource gets `managed-by=discovery-platform` and
  `dp-component=<component>` tags**, via provider `default_tags`. The
  inverse — adding tags to an *estate* resource — breaks the estate's own
  grouping tests. Two different Terraform states, two different tagging
  rules, never mix them.
- **The `dp-collector` role is read-only. Full stop.** Any write API
  showing up in a collector (not your box, but adjacent) is treated as a
  defect, not a feature.
- **No workload subnet routes to an internet gateway.** `P2-01`'s own
  acceptance check is a Terraform `check` block that fails the plan if a
  `collector` or `data` route table ever gets a `0.0.0.0/0` route to the
  IGW. All egress goes through Network Firewall (a different task,
  `P2-02` — not yours, but your subnets are what it constrains).
- **Never use `dp-deployer` to touch estate resources, or `condor-bootstrap`
  to touch platform resources.** CloudTrail is how findings get
  corroborated later; crossing the identities pollutes that evidence for
  everyone.
- **Don't fix a planted estate defect "for security."** If you're staring
  at something in the estate that looks wrong while you're building a
  collector or dashboard against it, it's very likely intentional — check
  `answer-key/answer-key.yaml` before touching it. This is more Santiago's
  risk than yours, but `P2-06`'s License Manager task pulls real data from
  Facturación's deliberately-old SQL Server, so the same caution applies.
- **Never sleep-loop waiting for AWS data to appear** (CUR delivery,
  Compute Optimizer recommendations, CID dashboard provisioning all take
  real hours-to-days). Use the `wait` gate pattern — see how `P1-16`
  (`estate/verify/check_ready.py`) does it: build the check, run it, if
  it's not ready print what's missing and stop. The operator re-runs it
  later.

## Definition of done, every task (CLAUDE.md §8)

Same bar for all eight: acceptance commands pass with output pasted in
the PR; `ruff check`/`ruff format --check` and `terraform fmt -check`/
`validate` pass; no secret values anywhere in code, logs, fixtures or PR
text; `tasks/STATUS.md` updated; the PR states the new hourly cost (most
of your tasks have an explicit cost limit — `P2-01` is $0.90/hr, mostly
interface endpoints, state the count).

## Where things live

- Terraform: `platform/terraform/<area>/` (`base/`, `identity/`,
  `aws-services/`, `orchestration/`, `lakehouse/`, `processing/`,
  `validation/` — matches the `Paths` row in each task file).
- State bucket: `dp-tfstate-<acct>`, entirely separate from the estate's
  `condor-tfstate-<acct>`.
- dbt: `platform/dbt/`. Quick dashboard definitions: `platform/quick/`.
- Data contracts you should read before `P3-03`/`P4-01`:
  `docs/contracts/raw-envelope.schema.json`, `canonical-model.md`.

## If you get stuck

Read the task file itself first (`tasks/P2-01.md` etc.) — it's more
detailed than this doc and is the actual spec. If a task's "Stop and ask
if" condition (or `CLAUDE.md` §2's general one) applies, that's a real
stop, not a suggestion to push through.

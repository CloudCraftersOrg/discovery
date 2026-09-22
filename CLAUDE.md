# CLAUDE.md — Condor Discovery PoC

Read this file completely before starting any task. It overrides your defaults. A task file overrides this file only where the task says so explicitly.

## 1. What this repository is

A proof of concept for EPAM AWS Solutions LATAM's **Cloud Discovery and Modernization Assessment** offering, AWS-to-AWS scenario only.

Two things live in one AWS account:

- **The estate** — a fictional retailer, *Mercado Cóndor*, deliberately built with known defects. It is a test fixture.
- **The discovery platform** — the product. It collects infra, apps and pipelines data from the estate, stores it, processes it into dashboards, and produces a business case handed to the AWS Transform offering.

Success is measured by one file: `answer-key/answer-key.yaml`. The platform must find every item in it and nothing false.

## 2. How to work a task

1. You are given exactly one task ID, for example `P2-08`. Open `tasks/P2-08.md`.
2. Check `tasks/STATUS.md`. Every task in **Depends** must be `done`. If not, stop and report which dependency is missing.
3. Read every file the task lists under **Read first**.
4. Work only inside the paths listed under **Paths**. If you need to change anything outside them, stop and ask.
5. Implement. Run every command under **Acceptance**. All must pass.
6. Update `tasks/STATUS.md`: set the task to `done`, or to `blocked` with a one-line reason.
7. Open one pull request per task. Title: `P2-08: <task title>`. Body: acceptance output, decisions made, anything a reviewer must check.

If the task has a **Gate**, respect it:

| Gate | Meaning |
|---|---|
| `none` | Proceed end to end, including apply. |
| `review` | Open the PR and stop. A human merges. |
| `approve-apply` | Run `plan`, post the plan in the PR, stop. Apply only after a human comments `approved`. |
| `human-action` | The task needs something only a human can do. Do the preparation, write exact instructions in `tasks/HANDOFF-<ID>.md`, stop. |
| `wait` | A time-based readiness check. Run the check script; if it fails, report the remaining condition and stop. Never sleep-loop. |

### Stop and ask

Stop, write the question in `tasks/BLOCKED-<ID>.md`, set STATUS to `blocked`, and end the session when:

- Anything in the task conflicts with this file or with another task.
- An AWS API, service feature, version or AMI the task names does not exist or behaves differently than described.
- Estimated run cost of what you are about to create exceeds the task's cost limit, or USD 1.50/hour if none is given.
- You would need to invent semantics the task does not define: a confidence value, a rule threshold, a schema field, a finding.
- The account guard fails.

Never guess past a stop condition. A blocked task is cheap; a wrong assumption poisons every downstream task.

## 3. Account and environment

| Variable | Value | Notes |
|---|---|---|
| `CONDOR_ACCOUNT_ID` | set by operator | The only account anything may touch |
| `HOME_REGION` | `us-east-1` | Estate, platform, CUR, Cost Optimization Hub — everything lives here, in one VPC (ADR-044-network-consolidation) |
| `DENIED_REGION` | `sa-east-1` | One canary resource; the collector is denied here on purpose |
| `GITHUB_ORG` | set by operator | Hosts estate app repos |

**One VPC, one region (ADR-044-network-consolidation).** There is no `SECOND_REGION` — Promo 2024's planted findings (AK-COV-04, AK-INF-07, AK-PIP-08) live in an isolated subnet of the single VPC instead of a second-region VPC. Everything is built to `terraform destroy` cleanly and re-`apply` on demand: `force_destroy` on every bucket this account owns, no deletion protection anywhere, no resource that blocks a clean teardown.

**Bootstrap identity, revised.** `condor-bootstrap` and `dp-deployer` do not hold AWS-managed `AdministratorAccess` — the human operator's own session (`AIDiscoveryAccess`, scoped to `condor-*`/`dp-*` resource names) cannot attach that policy to anything it creates, by design. Each role instead carries a customer-managed policy scoped the same way `AIDiscoveryAccess` is, plus `condor-sandbox-boundary`. `dp-deployer` is not created until platform work starts; only `condor-bootstrap` exists while the estate is the only thing being built.

Profiles:

- `condor-bootstrap` — used for everything under `estate/`.
- `dp-deployer` — used for everything under `platform/`.
- Human-identity keys (`dev.maria`, `dev.juan`) are used only by the tasks that say so.

**Account guard.** Before any AWS write, run `scripts/guard.sh <estate|platform>`. It fails if the caller account is not `CONDOR_ACCOUNT_ID`, or the role does not match the area. Every Makefile target that writes to AWS calls it first.

## 4. The estate is a fixture. Defects are intentional.

Tasks under `estate/` build things that look wrong: admin roles, static keys, a plaintext token, an outdated Jenkins, untagged servers, drift. This is required.

- **Build defects exactly as specified. Never fix, harden or "improve" them.**
- Mark each one in code with `PLANTED: <answer-key ID>`, for example `# PLANTED: AK-PIP-05`.
- Compensating controls are mandatory and are the only hardening allowed:
  - Every planted admin role or user also gets the permissions boundary `condor-sandbox-boundary`.
  - Nothing in the estate is reachable from the internet.
  - The planted token is a canary: `CONDOR-CANARY-` followed by a UUID. Never a real credential.
- **Tags on estate resources: exactly the tags the task lists, nothing else.** Do not set provider `default_tags` in estate Terraform. Untagged resources are part of the test. AWS system tags (`aws:*`) are expected and fine.
- Resources created by scripts under `estate/clickops/` must never be imported into any IaC state. Record their IDs in `estate/clickops/manifest.json` for teardown.

## 5. The platform is the product. Normal engineering standards apply.

- Every platform resource carries these tags: `managed-by=discovery-platform`, `dp-component=<component>`. Use provider `default_tags` in platform Terraform.
- Least privilege. No wildcard actions except the read-only managed policies a task names.
- The collector role is **read-only**. Any write API in a collector is a defect.
- No workload subnet routes to an internet gateway. All egress passes Network Firewall with a domain allowlist.
- Never log or store a secret value. Secret *names* and *references* only.

## 6. Tooling

| Concern | Choice |
|---|---|
| IaC | Terraform. Latest stable 1.x and latest AWS provider at execution time, pinned exactly in `versions.tf`. CloudFormation only for Tienda. |
| Terraform state | Estate: bucket `condor-tfstate-<acct>`. Platform: bucket `dp-tfstate-<acct>`. Never shared. |
| Lambda code | Python 3.12, `uv` for dependencies, `boto3`. One package per function under `platform/<area>/<name>/`. |
| Tests | `pytest`. Unit tests are offline, using `moto` or recorded fixtures under `tests/fixtures/`. AWS-touching tests are marked `@pytest.mark.aws`. |
| Lint | `ruff check` and `ruff format --check` must pass. `terraform fmt -check` and `terraform validate` must pass. |
| Transforms | `dbt-athena` on Iceberg tables, run from a Lambda container image stored in private ECR repo `dp-dbt`. |
| Canonical store | Aurora PostgreSQL Serverless v2, accessed through the RDS Data API. |
| Schemas | JSON Schema draft 2020-12 under `docs/contracts/`. |
| Dashboards | Amazon Quick, defined as code through the QuickSight API definitions under `platform/quick/`. |

Resolve versions at execution time (EKS, Jenkins LTS, AMIs, providers). Record what you chose and why in the PR and, where the task asks, in an ADR.

## 7. Data contracts (summary; full definitions in `docs/contracts/`)

**Raw record envelope** — every collector writes JSON Lines, gzip:

```
raw/engagement=<slug>/run_id=<ulid>/domain=<infra|apps|pipelines>/source=<collector>/account=<account_id>/region=<region>/part-<n>.jsonl.gz
```

Each line:

```json
{
  "envelope_version": "1",
  "run_id": "01J...",
  "collector": "ecs",
  "collector_version": "0.1.0",
  "domain": "apps",
  "account_id": "123456789012",
  "region": "us-east-1",
  "observed_at": "2026-09-15T12:00:00Z",
  "resource_type": "AWS::ECS::Service",
  "resource_id": "arn:aws:ecs:...",
  "record_kind": "resource|relation|event|metric|coverage",
  "payload": {},
  "payload_sha256": "..."
}
```

`record_kind=coverage` is how a collector reports what it could not reach, with `payload.reason` one of `access_denied`, `not_found`, `unreachable`, `throttled`, `unsupported`.

`engagement` is `condor` in this repository and a client slug elsewhere; `account` is the 12-digit account the record was collected *from*, which is not always the account the platform runs in. Both partitions have cardinality 1 here and are the difference between a pruned query and a full scan at a client. Ordering is by how queries filter: engagement and run first, account and region deep.

**Confidence ladder for grouping** (fixed, do not change):

| Signal | Confidence |
|---|---|
| CloudFormation stack or Terraform state membership | 0.95 |
| Runtime primitive: ECS service, EKS namespace, ELB target group, ASG | 0.90 |
| Pipeline deploy target | 0.85 |
| Resource Group or tag | 0.75 |
| Flow logs, fallback only | 0.50 |

**Every finding** carries `value_usd`, a band `{low, expected, high, assumption}` and `realization_lag_days`. No finding reaches a dashboard or the business case without all three.

## 8. Definition of done, every task

- Acceptance commands pass, output pasted in the PR.
- Lint and format checks pass.
- No secret values in code, logs, fixtures or PR text.
- `PLANTED:` markers present for every estate defect the task creates.
- Answer-key items the task touches are referenced by ID in the PR.
- `tasks/STATUS.md` updated.
- Costs: new hourly run cost stated in the PR.

## 9. Things agents commonly get wrong here

- Adding tags or `default_tags` to estate resources. Breaks grouping tests.
- Fixing a planted defect "for security". Breaks the answer key.
- Using the platform role to build estate resources, or the reverse. Pollutes CloudTrail evidence.
- Importing a clickops resource into Terraform. Breaks IaC coverage.
- Using GitHub-hosted runners for Pagos deploys. They cannot reach the private EKS endpoint. Pagos uses the self-hosted runner.
- Treating the Jenkins controller or the GitHub runner as part of an application. They are shared platform tooling.
- Copying flow-log or CUR files into raw storage wholesale. Collectors read and summarise them; see the task.
- Sleeping in a loop to wait for AWS data to appear. Use the `wait` gate.

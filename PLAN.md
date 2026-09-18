# PLAN.md — Condor Discovery PoC task plan

58 tasks in five phases, ordered by dependency. No dates. Each task is one Claude Code session, one pull request, and closes on its acceptance criteria. Task definitions live in `tasks/<ID>.md`; standing rules in `CLAUDE.md`.

## How to dispatch agents

1. A task is **ready** when its status is `todo` and every task in its Depends column is `done` in `tasks/STATUS.md`.
2. Start one agent per ready task, each in its own git worktree and branch `task/<ID>`. Prompt: `Execute task <ID>. Follow CLAUDE.md.`
3. Cap parallel agents at the number of humans available to clear gates. Four contributors means at most four agents waiting on review at once.
4. When an agent stops on a gate or a `BLOCKED-<ID>.md`, a human resolves it before the next agent starts on a dependent task.
5. `Wave` is the earliest dependency depth. Tasks in the same wave never depend on each other and can run in parallel.

Streams: **I** Infra, **P** Product, **I+P** both. Gates: `none`, `review`, `approve-apply`, `human-action`, `wait` (see `CLAUDE.md` section 2).

## Phase 1 · Mount the estate to detect

| Task | Title | Stream | Depends | Gate | Wave |
|---|---|---|---|---|---|
| [P1-01](tasks/P1-01.md) | Repository scaffold, identities and guardrails | I | — | `approve-apply` | 0 |
| [P1-02](tasks/P1-02.md) | Answer key | P | P1-01 | `review` | 1 |
| [P1-03](tasks/P1-03.md) | Account telemetry baseline | I | P1-01 | `approve-apply` | 1 |
| [P1-04](tasks/P1-04.md) | Estate networking | I | P1-03 | `approve-apply` | 2 |
| [P1-05](tasks/P1-05.md) | Estate application source repositories | P | P1-01 | `review` | 1 |
| [P1-06](tasks/P1-06.md) | Tienda | I | P1-04, P1-05 | `approve-apply` | 3 |
| [P1-07](tasks/P1-07.md) | Pagos | I | P1-04, P1-05 | `approve-apply` | 3 |
| [P1-08](tasks/P1-08.md) | Inventario (clickops) | I | P1-06 | `approve-apply` | 4 |
| [P1-09](tasks/P1-09.md) | Facturación (clickops) | I | P1-04 | `approve-apply` | 3 |
| [P1-10](tasks/P1-10.md) | Reportes (clickops) | I | P1-04, P1-05 | `approve-apply` | 3 |
| [P1-11](tasks/P1-11.md) | Jenkins controller | I | P1-10 | `approve-apply` | 4 |
| [P1-12](tasks/P1-12.md) | Promo 2024 (clickops, second region) | I | P1-04 | `approve-apply` | 3 |
| [P1-13](tasks/P1-13.md) | Planted human changes: laptop apply and console drift | I | P1-07, P1-15 | `approve-apply` | 6 |
| [P1-14](tasks/P1-14.md) | History and traffic generators | P | P1-06, P1-07, P1-08, P1-11, P1-15 | `review` | 6 |
| [P1-15](tasks/P1-15.md) | Estate verification and history start | I+P | P1-06, P1-07, P1-08, P1-09, P1-10, P1-11, P1-12 | `none` | 5 |
| [P1-16](tasks/P1-16.md) | Data readiness gate | I+P | P1-13, P1-14, P1-15 | `wait` | 7 |

## Phase 2 · Build the collectors

| Task | Title | Stream | Depends | Gate | Wave |
|---|---|---|---|---|---|
| [P2-01](tasks/P2-01.md) | Platform network and storage base | I | P1-01, P1-04 | `approve-apply` | 3 |
| [P2-02](tasks/P2-02.md) | Controlled egress | I | P2-01 | `approve-apply` | 4 |
| [P2-03](tasks/P2-03.md) | Private path to the estate | I | P2-01, P1-07, P1-11 | `approve-apply` | 5 |
| [P2-04](tasks/P2-04.md) | Collector identities | I | P2-01, P1-07, P1-11, P1-05 | `human-action` | 5 |
| [P2-05](tasks/P2-05.md) | Contracts and canonical model | I+P | P1-02 | `review` | 2 |
| [P2-06](tasks/P2-06.md) | AWS-provided analytics services | I | P1-03, P1-09 | `approve-apply` | 4 |
| [P2-07](tasks/P2-07.md) | Collector framework | I | P2-04, P2-05 | `review` | 6 |
| [P2-08](tasks/P2-08.md) | Infra collectors: inventory and IaC | I | P2-07 | `none` | 7 |
| [P2-09](tasks/P2-09.md) | Infra collectors: runtime, data and resilience | I | P2-07 | `none` | 7 |
| [P2-10](tasks/P2-10.md) | Infra collectors: utilisation, traffic, cost and AWS service outputs | I | P2-07, P1-16 | `none` | 8 |
| [P2-11](tasks/P2-11.md) | Lifecycle reference table | P | P2-05 | `review` | 3 |
| [P2-12](tasks/P2-12.md) | Apps collectors | I | P2-07, P2-03 | `none` | 7 |
| [P2-13](tasks/P2-13.md) | GitHub collector | I | P2-07, P2-02, P2-04 | `none` | 7 |
| [P2-14](tasks/P2-14.md) | AWS delivery collectors | I | P2-07 | `none` | 7 |
| [P2-15](tasks/P2-15.md) | Jenkins collector | I | P2-07, P2-03, P2-02, P2-04 | `none` | 7 |
| [P2-16](tasks/P2-16.md) | Pipeline definition parsers | P | P2-05 | `review` | 3 |
| [P2-17](tasks/P2-17.md) | Collector contract and source traceability tests | P | P2-08, P2-09, P2-10, P2-11, P2-12, P2-13, P2-14, P2-15, P3-03 | `none` | 9 |

## Phase 3 · Gather and store

| Task | Title | Stream | Depends | Gate | Wave |
|---|---|---|---|---|---|
| [P3-01](tasks/P3-01.md) | Scheduling and ingest orchestration | I | P2-17 | `approve-apply` | 10 |
| [P3-02](tasks/P3-02.md) | Staging and contract gate | I | P3-01, P3-03 | `none` | 11 |
| [P3-03](tasks/P3-03.md) | Lakehouse tables | I | P2-05, P2-01 | `approve-apply` | 4 |
| [P3-04](tasks/P3-04.md) | Scope and self-exclusion | I | P3-02 | `none` | 12 |
| [P3-05](tasks/P3-05.md) | Retention, audit and data destruction | I | P3-02 | `review` | 12 |
| [P3-06](tasks/P3-06.md) | Coverage views | P | P3-04 | `review` | 13 |

## Phase 4 · Process for dashboards

| Task | Title | Stream | Depends | Gate | Wave |
|---|---|---|---|---|---|
| [P4-01](tasks/P4-01.md) | Canonical store and processing runtime | I | P3-02, P2-05 | `approve-apply` | 12 |
| [P4-02](tasks/P4-02.md) | Identity resolution | I | P4-01, P1-16 | `none` | 13 |
| [P4-03](tasks/P4-03.md) | Grouping specification | P | P2-05 | `review` | 3 |
| [P4-04](tasks/P4-04.md) | Grouping engine | I | P4-02, P4-03 | `none` | 14 |
| [P4-05](tasks/P4-05.md) | Dependency derivation | P | P4-04 | `none` | 15 |
| [P4-06](tasks/P4-06.md) | Pipeline linking, manual deploys and DORA | P | P4-04, P2-16 | `none` | 15 |
| [P4-07](tasks/P4-07.md) | Finding rules | P | P4-05, P4-06, P2-11 | `review` | 16 |
| [P4-08](tasks/P4-08.md) | Decommission corroboration | P | P4-07 | `review` | 17 |
| [P4-09](tasks/P4-09.md) | Monetization | P | P4-07, P4-08 | `review` | 18 |
| [P4-10](tasks/P4-10.md) | Replay test | I | P4-09 | `none` | 19 |
| [P4-11](tasks/P4-11.md) | Dashboards | P | P4-09, P3-06 | `human-action` | 19 |
| [P4-12](tasks/P4-12.md) | Answer key evaluation harness | P | P4-10, P4-11 | `none` | 20 |

## Phase 5 · Business case for AWS Transform

| Task | Title | Stream | Depends | Gate | Wave |
|---|---|---|---|---|---|
| [P5-01](tasks/P5-01.md) | Validation workbooks | P | P4-12 | `review` | 21 |
| [P5-02](tasks/P5-02.md) | Validation orchestration | I | P5-01 | `approve-apply` | 22 |
| [P5-03](tasks/P5-03.md) | Validation scenario run | P | P5-02 | `review` | 23 |
| [P5-04](tasks/P5-04.md) | Business case generator | P | P5-03, P4-09 | `review` | 24 |
| [P5-05](tasks/P5-05.md) | Modernization candidates and AWS Transform handoff | I+P | P5-04 | `human-action` | 25 |
| [P5-06](tasks/P5-06.md) | Business case dashboard | P | P5-04, P4-11 | `human-action` | 25 |
| [P5-07](tasks/P5-07.md) | End-to-end rebuild, cost, runbook and demo | I | P5-05, P5-06 | `human-action` | 26 |

## Human gates, in order

These are the points where agents stop and a person must act. Plan who owns each.

| Task | Gate | What the human does |
|---|---|---|
| P1-01 | `approve-apply` | Read the plan in the PR, comment `approved` |
| P1-02 | `review` | Review and merge the PR |
| P1-03 | `approve-apply` | Read the plan in the PR, comment `approved` |
| P1-04 | `approve-apply` | Read the plan in the PR, comment `approved` |
| P1-05 | `review` | Approve the planted vulnerable dependency versions |
| P1-06 | `approve-apply` | Complete the CodeConnections handshake (handoff), approve apply |
| P1-07 | `approve-apply` | Read the plan in the PR, comment `approved` |
| P1-08 | `approve-apply` | Read the plan in the PR, comment `approved` |
| P1-09 | `approve-apply` | Read the plan in the PR, comment `approved` |
| P1-10 | `approve-apply` | Read the plan in the PR, comment `approved` |
| P1-11 | `approve-apply` | Approve the planted Jenkins plugin version, then approve apply |
| P1-12 | `approve-apply` | Read the plan in the PR, comment `approved` |
| P1-13 | `approve-apply` | Read the plan in the PR, comment `approved` |
| P1-14 | `review` | Review and merge the PR |
| P1-16 | `wait` | Wait for CUR, Compute Optimizer and pipeline history, then re-run |
| P2-01 | `approve-apply` | Read the plan in the PR, comment `approved` |
| P2-02 | `approve-apply` | Read the plan in the PR, comment `approved` |
| P2-03 | `approve-apply` | Read the plan in the PR, comment `approved` |
| P2-04 | `human-action` | Create and install the GitHub App (org owner) |
| P2-05 | `review` | Both streams sign off the contracts |
| P2-06 | `approve-apply` | Read the plan in the PR, comment `approved` |
| P2-07 | `review` | Review and merge the PR |
| P2-11 | `review` | Review and merge the PR |
| P2-16 | `review` | Review and merge the PR |
| P3-01 | `approve-apply` | Read the plan in the PR, comment `approved` |
| P3-03 | `approve-apply` | Read the plan in the PR, comment `approved` |
| P3-05 | `review` | Review and merge the PR |
| P3-06 | `review` | Review and merge the PR |
| P4-01 | `approve-apply` | Read the plan in the PR, comment `approved` |
| P4-03 | `review` | Both streams sign off grouping semantics |
| P4-07 | `review` | Review and merge the PR |
| P4-08 | `review` | Review and merge the PR |
| P4-09 | `review` | Review and merge the PR |
| P4-11 | `human-action` | Quick subscription, author user and data-source permissions |
| P5-01 | `review` | Review and merge the PR |
| P5-02 | `approve-apply` | Read the plan in the PR, comment `approved` |
| P5-03 | `review` | Review and merge the PR |
| P5-04 | `review` | Review and merge the PR |
| P5-05 | `human-action` | Transform offering team confirms the handoff schema |
| P5-06 | `human-action` | Follow `tasks/HANDOFF-<ID>.md` |
| P5-07 | `human-action` | Outside engineer runs the rebuild from the runbook |

## Longest path

The critical chain runs through the data readiness wait (P1-16), the collectors, ingest, and every processing step in sequence. Everything off this chain can run ahead in parallel:

- Product specs P2-05, P2-11, P2-16 and P4-03 start as soon as the answer key exists. They unblock the engines later.
- The platform base P2-01 to P2-04 runs alongside estate construction P1-06 to P1-12.
- P1-16 is a time gate. Start the estate early; nothing in Phase 4 can pass before it.

## Corrections to the earlier design, recorded here and in ADRs

- **ECR (ADR-039):** the dbt Lambda container image requires a private ECR repository. "No ECR" is corrected to "no ECR for workloads; one repo for the dbt image".
- **Internet gateway (ADR-040):** NAT requires an internet gateway. "No internet gateway" is corrected to "no workload subnet routes to it; all egress passes Network Firewall".
- **Pagos runner (ADR-042):** GitHub-hosted runners cannot reach a private EKS endpoint. Pagos deploys through a self-hosted runner, which is classified as platform tooling.
- **Redaction:** redaction runs inside the collector writer, before anything reaches Object Lock storage, where a leaked secret could not be deleted.

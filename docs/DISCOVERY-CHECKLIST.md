# Discovery checklist (agent-oriented)

Audience: an agent building or running the Phase 2+ discovery platform
(collectors, grouping/dependency engine, finding rules, DORA/business-case
generators) against the Condor estate, or an agent grading a Phase 4 run.
This is not a human-readable summary — every row is a concrete, checkable
condition, sourced directly from `answer-key/answer-key.yaml` (57 items).
`estate/verify/check_planted.py` is the reference implementation for how
each one is verified today from the estate side; `checked_in_phase` says
which platform phase is expected to independently reproduce it.

Two tiers:

- **MUST** (`checked_in_phase: 2`, 43 items) — the foundational discovery
  layer: coverage, app grouping, dependencies, infra/app/pipeline findings.
  A run that misses any of these has not actually discovered the estate.
- **SHOULD** (`checked_in_phase: 4` or `5`, 14 items) — built on top of a
  correct MUST layer: derived metrics, quality bars, and the business-case
  chain. Several need accumulated time-series data (P1-16 gates this) or a
  human validation step (Phase 5) that no agent can complete alone.

Resource pointers below use the same names as `estate/verify/refs.json`
and `estate/clickops/manifest.json` — resolve those files live rather than
trusting IDs pasted here, since clickops resources get replaced (e.g.
`reportes-worker` was recreated once already, see `tasks/STATUS.md` P1-16).

## MUST — coverage (AK-COV-*)

| ID | Subject | Expect | Evidence sources |
|---|---|---|---|
| AK-COV-01 | `denied_region_canary` (SSM param `/condor/canary` in `sa-east-1`) | collector run against the denied region still succeeds overall, but returns `access_denied` for this resource | all regional collectors |
| AK-COV-02 | `reportes-worker` instance | absent from SSM inventory (SSM Agent deliberately stopped+disabled) | ssm_inventory, config |
| AK-COV-03 | anything tagged `managed-by=discovery-platform` | excluded from scope and from cost (the platform must not appear as a discovered/costed resource) | tagging, cur |
| AK-COV-04 | `promo-2024-instance` | absent from SSM inventory (no instance profile at all) | ssm_inventory, config |

## MUST — app grouping (AK-GRP-*)

| ID | Subject | Expect | Evidence sources |
|---|---|---|---|
| AK-GRP-01 | tienda | grouped via CloudFormation stack membership, confidence 0.95 | cloudformation |
| AK-GRP-02 | pagos | grouped via Terraform state membership, confidence 0.95, corroborated by k8s namespace `pagos` | tfstate, kubernetes |
| AK-GRP-03 | inventario | grouped via ECS service membership, confidence 0.9 | ecs |
| AK-GRP-04 | facturacion | grouped via `tag:app=facturacion` only, confidence 0.75 (weaker signal, single instance, no IaC) | tagging |
| AK-GRP-05 | reportes | grouped via ASG + ELB target group membership, confidence 0.9 | asg, elb |
| AK-GRP-06 | reportes + `reportes-worker` | worker attaches to reportes ONLY via flow logs, confidence 0.5, state `pre_validation` (deliberately weak/ambiguous signal — no tags, no IaC, no SG reference) | flowlogs |
| AK-GRP-07 | `promo-2024-instance` | NOT grouped into any app (ungrouped by design) | config |
| AK-GRP-08 | `condor-jenkins` | classified `platform_tooling`, not a member of any app | ssm_inventory, config |
| AK-GRP-09 | `condor-gh-runner` | classified `platform_tooling` | ssm_inventory, config |
| AK-GRP-10 | anything tagged `managed-by=cloud-governance`, plus network/state resources | classified `shared_infrastructure`, not an application | tagging, tfstate |
| AK-GRP-11 | whole estate | metric: reports `declared_count` / `inferred_count` / `ungrouped_count` | derived |

## MUST — dependencies (AK-DEP-*, AK-PIP-01)

| ID | Subject | Expect | Evidence sources |
|---|---|---|---|
| AK-DEP-01 | tienda → pagos | direction `tienda->pagos` (checkout calling `/pay`) | flowlogs, elb |
| AK-DEP-02 | inventario → tienda's RDS | direction `inventario->tienda_rds` (cross-app shared-DB read) | flowlogs, rds |
| AK-PIP-01 | pipeline↔app links | tienda: CodePipeline + Jenkins (dual); pagos: GitHub Actions + Jenkins (dual); reportes: Jenkins only; each confirmed by a real CloudTrail event, not just config presence | codepipeline, github, jenkins, cloudtrail, parsers |
| AK-DEP-03 | `facturacion-nightly-export` (Jenkins job, no source repo) | kind `operational_automation` — a scheduled job, not a deploy pipeline | jenkins, cloudtrail |

## MUST — infra findings (AK-INF-01 to 09, excluding AK-INF-10)

| ID | Subject | Expect | Evidence sources |
|---|---|---|---|
| AK-INF-01 | tienda ASG | `asg_rightsizing_opportunity` | compute_optimizer, cost_optimization_hub |
| AK-INF-02 | account-wide | `no_savings_plans_coverage` | cost_optimization_hub, cur |
| AK-INF-03 | pagos EKS | `eks_version_nearest_eos` (1.34, oldest in standard support at build time) | eks, lifecycle |
| AK-INF-04 | facturacion | `windows_server_2016_extended_support_eos` | ssm_inventory, lifecycle |
| AK-INF-05 | condor-jenkins | `amazon_linux_2_past_eos` | ssm_inventory, lifecycle |
| AK-INF-06 | `JENKINS_HOME` EBS volume | `no_backup` | backup, ebs |
| AK-INF-07 | promo-2024-instance | `unattached_ebs_and_unused_eip` | config, cost_optimization_hub |
| AK-INF-08 | pagos's `condor-pagos-db` param group | `aurora_parameter_drift_from_tfstate` (planted by P1-13's console drift) | tfstate, rds, cloudtrail |
| AK-INF-09 | facturacion | `sql_server_standard_license_included` | license_manager, ssm_inventory |

## MUST — app findings (AK-APP-*)

| ID | Subject | Expect | Evidence sources |
|---|---|---|---|
| AK-APP-01 | tienda (also condor-reportes) | `outdated_dependency_with_advisory` (`requests==2.30.0`, CVE-2023-32681) | github |
| AK-APP-02 | inventario reading tienda's DB | `shared_database_with_tienda` | flowlogs, rds, ecs |
| AK-APP-03 | inventario | `plaintext_secret_in_task_definition` (`API_TOKEN`), value must be redacted in the finding output | ecs, redaction log |
| AK-APP-04 | inventario, reportes, facturacion | `unmonitored_apps` (no CloudWatch alarms) | cloudwatch_alarms |
| AK-APP-05 | whole estate | metric: language per app — tienda Python, pagos Node.js, inventario Python, reportes Java | github, ecs, kubernetes |
| AK-APP-06 | whole estate | metric: entry points per app, derived from private DNS + listeners | route53, elb |

## MUST — pipeline findings (AK-PIP-02 to 11, excluding AK-PIP-12)

| ID | Subject | Expect | Evidence sources |
|---|---|---|---|
| AK-PIP-02 | inventario | `manual_deploy`, actor `dev.juan`, no matching pipeline run | ecr, cloudtrail, image_trace |
| AK-PIP-03 | pagos | `manual_deploy`, actor `dev.maria`, channel `tfstate_write` | tfstate_history, cloudtrail |
| AK-PIP-04 | condor-jenkins credential store | `static_keys` held for `dev.juan`, `dev.maria`, `svc.jenkins-export` | iam, jenkins |
| AK-PIP-05 | `tienda-codebuild-role`, `condor-jenkins-instance-profile` | `admin_roles` (AdministratorAccess attached) | iam |
| AK-PIP-06 | reportes | `no_approval_before_deploy` | jenkins, parsers |
| AK-PIP-07 | `facturacion-nightly-export` | `defined_only_in_jenkins` (no source repo backs it) | jenkins |
| AK-PIP-08 | `condor-promo-2024` pipeline | `dead_pipeline`, target stack missing | codepipeline, cloudformation |
| AK-PIP-09 | condor-inventario ECR repo | `mutable_tags_scan_off_latest_in_use` | ecr, ecs |
| AK-PIP-10 | condor-jenkins | `outdated_lts_plugin_with_advisory_builds_on_controller` (matrix-auth 3.2.9) | jenkins |
| AK-PIP-11 | inventario, facturacion | `no_pipeline` | derived |

---

## SHOULD — accumulated-data metrics (need P1-16 to gate this; needs time)

| ID | Subject | Expect | Evidence sources | Notes |
|---|---|---|---|---|
| AK-INF-10 | whole estate | metric: `iac_coverage`, clickops list must equal `estate/clickops/manifest.json` | config, cloudformation, tfstate | pure config comparison, no time dependency |
| AK-PIP-12 | tienda, pagos, reportes | metric: DORA (deploy frequency, change failure rate, lead time), tolerance vs `estate/harness/ledger.jsonl` (deploy_frequency exact, CFR ±5pp, lead time ±10%) | codepipeline, github, jenkins | needs P1-14's harness to have run long enough — see `estate/harness/expected_metrics.py` |
| AK-DEC-01 | promo-2024-instance | `decommission_candidate`: CPU p95 < 2%, 0 accepted flows, 0 changes/deploys, quantified savings | cloudwatch, flowlogs, config, cloudtrail, cur | needs a real observation window, not just a point-in-time check |
| AK-MAT-01 | whole estate | metric: Well-Architected workload review results | wellarchitected | requires a WA Tool review to actually exist |
| AK-QLT-01 | whole estate | identity resolution precision ≥0.95, recall ≥0.9 | derived | grades the platform's own resolution logic |
| AK-QLT-02 | whole estate | replay test: delete Aurora + derived tables, rebuild from raw, marts identical | derived | correctness/idempotency check on the pipeline itself |

## SHOULD — business case chain (Phase 5, needs a human in the loop)

| ID | Subject | Expect | Notes |
|---|---|---|---|
| AK-VAL-01 | reportes-worker / facturacion | owner reassigns worker's true owning app → facturacion's cost and business case change accordingly | not automatable — needs a real human decision to observe |
| AK-VAL-02 | promo-2024-instance | state `unowned` → escalated to a sponsor who signs off → produces a staged stop/observe/terminate plan | same — human sign-off is part of the expected finding |
| AK-BC-01 | account-wide | baseline reconciles to CUR within 1% (±5pt tolerance), platform's own cost excluded | cur |
| AK-BC-02 | every line/finding | has `value_usd`, `band`, `realization_lag_days` | derived |
| AK-BC-03 | account-wide | target run-rate line present, sourced from AWS Transform (placeholder acceptable) | derived |
| AK-BC-04 | facturacion, inventario, pagos, reportes, condor-jenkins | modernization candidates reported, each with evidence links | derived |
| AK-BC-05 | account-wide | handoff package validates against `docs/contracts/transform-handoff.schema.json` | derived |

---

## Cross-cutting gotchas worth knowing before building collectors

- **Confidence is intentionally uneven.** AK-GRP-04 (facturacion, tag-only) and AK-GRP-06 (reportes-worker, flow-log-only, `pre_validation`) are deliberately weak-signal groupings — a collector that demands IaC/tag corroboration everywhere will wrongly drop these.
- **Two apps have dual pipelines on purpose** (AK-PIP-01) — tienda and pagos each run both their original pipeline (CodePipeline / GitHub Actions) and a parallel Jenkins pipeline (ADR-046). A collector that assumes one pipeline per app will under-report.
- **CloudTrail Event History does not reliably surface S3 data events** for this trail (confirmed live during P1-13) — anything evidenced by `cloudtrail` against tfstate writes needs the trail's own delivered S3 log objects read directly, not `LookupEvents`.
- **CUR 2.0 and flow logs are Parquet, not Athena-queryable out of the box** — `estate/verify/check_ready.py` reads both directly from S3 with DuckDB's `httpfs`; a collector can do the same without standing up Athena tables.
- **`estate/harness/ledger.jsonl` is the ground truth for AK-PIP-12's tolerance**, not the platform's own derived history — don't let the platform grade itself against its own output.
- **`estate/clickops/manifest.json` is the authoritative non-IaC resource list** for AK-INF-10 — anything clickops-created that's missing from it is itself a bug, not a finding.

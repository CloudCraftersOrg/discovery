# Task status

Values: `todo`, `in_progress`, `blocked`, `review`, `done`. Agents update their own row only.

| Task | Title | Status | Note |
|---|---|---|---|
| P1-01 | Repository scaffold, identities and guardrails | done | Applied 2026-09-18. dp-deployer deferred to platform work (ADR-045). |
| P1-02 | Answer key | done | 57 items, validate.py passes. kind enum extended with "quality" to match the table (P1-02's field list omitted it) — see PR. |
| P1-03 | Account telemetry baseline | done | Applied 2026-09-18, verified live (Config both regions, CloudTrail, CUR2, Compute Optimizer, Cost Optimization Hub). Cost allocation tags skipped — management-account-only, see tasks/HANDOFF-P1-03.md. |
| P1-04 | Estate networking | done | Applied 2026-09-18: condor-vpc vpc-06f069857cd5a3612. Verified live: promo route table has no 0.0.0.0/0 route, flow logs ACTIVE. 0 warnings/errors on apply, unlike P1-03. |
| P1-05 | Estate application source repositories | done | 5 repos pushed to CloudCraftersOrg (private). Branch protection on condor-pagos skipped — needs GitHub Pro/Team for a private repo. |
| P1-06 | Tienda | blocked | Stack CREATE_COMPLETE — ALB/ASG/RDS/pipeline all live, verified. Blocked on human GitHub connection approval — tasks/HANDOFF-P1-06.md. |
| P1-07 | Pagos | todo | |
| P1-08 | Inventario (clickops) | todo | |
| P1-09 | Facturación (clickops) | done | Applied 2026-09-18, verified live: instance SSM-managed (condor-facturacion, Windows Server 2016 + SQL Server 2019 Standard, AMI Windows_Server-2016-English-Full-SQL_2019_Standard-2026.09.17), `AWS:Application` inventory shows SQL Server 2019. Instance type c5.large ($0.657/hr on-demand, US East N. Virginia — via Pricing API) — the smallest supported: t2/t3 rejected outright by the AMI ("Microsoft SQL Server is not supported for the instance type"), m5/c5/r5/m6i all start at `.large`. Added read-only `pricing:*Get*`/`DescribeServices` to condor-bootstrap-access to look this up authoritatively instead of guessing from scraped pricing pages. Tagged `app=facturacion` only (AK-GRP-04). No real bug beyond expected: Windows+SQL Server sysprep/first-boot took ~15min before SSM Agent registered, far longer than any Linux instance built so far — not a defect, just slower hardware bring-up. |
| P1-10 | Reportes (clickops) | done | Applied 2026-09-18, verified live: both ASG instances healthy in target group, HTTP /report reachable via ALB and Route53 (reportes.condor.internal), worker absent from SSM inventory, worker traffic confirmed in VPC flow logs. Fixed 3 bugs found during real deploy: appspec never shipped the systemd unit, service user never created, un-shaded jar hit NoClassDefFoundError on jackson-databind transitive deps. Same systemd-unit/user fixes proactively applied to condor-tienda. |
| P1-11 | Jenkins controller | todo | |
| P1-12 | Promo 2024 (clickops, isolated subnet) | done | Applied 2026-09-18, verified live: instance running with no instance profile (AK-COV-04), unattached 20GiB gp3 volume + unassociated EIP (AK-INF-07), pipeline ran once and its target stack was then deleted (AK-PIP-08) — `codepipeline get-pipeline` succeeds, `cloudformation describe-stacks` returns does-not-exist. Real bug found on first pipeline run: unquoted `PLANTED: AK-PIP-08` inside the CFN template's `Description:` broke YAML parsing (colon-space inside a plain scalar) — fixed by quoting the string. |
| P1-13 | Planted human changes: laptop apply and console drift | todo | |
| P1-14 | History and traffic generators | todo | |
| P1-15 | Estate verification and history start | todo | |
| P1-16 | Data readiness gate | todo | |
| P2-01 | Platform network and storage base | todo | |
| P2-02 | Controlled egress | todo | |
| P2-03 | Private path to the estate | todo | Rewritten for ADR-044 (no peering/Resolver) while doing P2-05 — not yet built. |
| P2-04 | Collector identities | todo | |
| P2-05 | Contracts and canonical model | done | All schemas validate (2020-12); 0001_init.sql applied + pytest passed against real Postgres 16; check_registry.py passes. ADR-041 rewritten for ADR-044, P2-03/P2-07/P3-04 updated to match. |
| P2-06 | AWS-provided analytics services | todo | |
| P2-07 | Collector framework | todo | |
| P2-08 | Infra collectors: inventory and IaC | todo | |
| P2-09 | Infra collectors: runtime, data and resilience | todo | |
| P2-10 | Infra collectors: utilisation, traffic, cost and AWS service outputs | todo | |
| P2-11 | Lifecycle reference table | todo | |
| P2-12 | Apps collectors | todo | |
| P2-13 | GitHub collector | todo | |
| P2-14 | AWS delivery collectors | todo | |
| P2-15 | Jenkins collector | todo | |
| P2-16 | Pipeline definition parsers | todo | |
| P2-17 | Collector contract and source traceability tests | todo | |
| P3-01 | Scheduling and ingest orchestration | todo | |
| P3-02 | Staging and contract gate | todo | |
| P3-03 | Lakehouse tables | todo | |
| P3-04 | Scope and self-exclusion | todo | |
| P3-05 | Retention, audit and data destruction | todo | |
| P3-06 | Coverage views | todo | |
| P4-01 | Canonical store and processing runtime | todo | |
| P4-02 | Identity resolution | todo | |
| P4-03 | Grouping specification | todo | |
| P4-04 | Grouping engine | todo | |
| P4-05 | Dependency derivation | todo | |
| P4-06 | Pipeline linking, manual deploys and DORA | todo | |
| P4-07 | Finding rules | todo | |
| P4-08 | Decommission corroboration | todo | |
| P4-09 | Monetization | todo | |
| P4-10 | Replay test | todo | |
| P4-11 | Dashboards | todo | |
| P4-12 | Answer key evaluation harness | todo | |
| P5-01 | Validation workbooks | todo | |
| P5-02 | Validation orchestration | todo | |
| P5-03 | Validation scenario run | todo | |
| P5-04 | Business case generator | todo | |
| P5-05 | Modernization candidates and AWS Transform handoff | todo | |
| P5-06 | Business case dashboard | todo | |
| P5-07 | End-to-end rebuild, cost, runbook and demo | todo | |

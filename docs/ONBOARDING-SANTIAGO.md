# Onboarding — Santiago, Jenkins discovery

**Repo: `CloudCraftersOrg/ai-discovery-tool`, not this one.** The framework
this originally pointed at (`P2-07`'s `dp_collect` package, `platform/
collectors/pipelines/jenkins/`) never got built in `discovery` — instead,
Alejandro built a full, more general version of this whole platform solo,
in `ai-discovery-tool`, in about 24 hours. Read this doc, then go work
there. `discovery` (this repo) is now a **reference**: its task files still
describe exactly what a Jenkins collector needs to do, they just get
implemented somewhere else.

You're pulling **evidence about Jenkins**, from Jenkins — jobs, builds,
plugins, credential references — read-only, into the platform's evidence
store. You are not touching the Jenkins controller itself, and you are not
writing anything back to it.

## The one thing to resolve before anything else

**As of right now, the `condor` engagement has `network_mode = "none"`**
(`terraform/10-network/engagements/condor.tfvars` in `ai-discovery-tool`) —
meaning the collector currently has **no network path into `condor-vpc` at
all**. `jenkins.condor.internal` is a VPC-private DNS name, same as every
other estate hostname (see `docs/ARCHITECTURE.md`'s "Reaching the apps"
section) — a Lambda outside that VPC cannot resolve or reach it, full stop.

This is different from what the old `discovery`-repo plan assumed: it took
for granted the collector Lambda would already be inside `condor-vpc`
(`ADR-044`, "one VPC"). `ai-discovery-tool` is a genuinely different
product — designed to reach *any* client's estate through one cross-account
role, not built inside Condor's own VPC — so that assumption doesn't carry
over automatically. GitHub reachability doesn't need this (it's a public
API over the internet); **Jenkins does**, and so would anything else that
depends on `condor-vpc`'s private DNS.

Concretely, someone needs to either flip `network_mode` to `managed` (and
peer or PrivateLink into `condor-vpc`) or `existing` (pointing at
`condor-vpc`'s own subnets directly) before your collector can be tested
against the real controller. Read `SPEC.md` §6 first, then raise this with
Alejandro and Oscar — it affects Oscar's `20-data`/Aurora work too (Aurora
needs a VPC), so it's likely already on someone's list, but confirm rather
than assume. **Don't try to solve the networking yourself** — that's
`terraform/10-network`, not your collector.

None of this blocks writing the collector itself — see below.

## What already exists for you, unblocked, right now

Unlike the old plan (which had you waiting on a `P2-07` framework that
didn't exist yet), `ai-discovery-tool`'s framework is **already built and
working**:

- `runtime/dp/evidence.py` — `Envelope`, `coverage()`, `EvidenceWriter`,
  `new_run_id()`. This is what you write records through.
- `runtime/dp/redact.py` — redaction rules for secrets, already covers AWS
  keys, GitHub tokens, private keys, JWTs, connection-string passwords,
  generic `password=`/`token=` assignments. Run anything Jenkins-adjacent
  through this before writing it — credential *values* must never reach
  evidence, only IDs/types/descriptions.
- `runtime/collector/handler.py` — the entrypoint. Right now
  `IMPLEMENTED = {"census", "traces"}`; Jenkins is one of ~34 collectors
  still to add, declared in `discovery`'s `docs/contracts/collectors.yaml`
  as `jenkins` (`domain: pipelines`, `cadence: hourly`, `regional: false`).

The pattern is a plain Python function, not a class hierarchy — copy the
shape of `collect_census`/`collect_traces` already in `handler.py`:

```python
def collect_jenkins(item, writer, engagement, run_id, account, region, session):
    try:
        # httpx, not boto3 - Jenkins is an HTTP API behind a token, same as GitHub
        ...
        writer.write(Envelope(..., source="jenkins", record_kind="resource", payload={...}))
    except Exception as exc:  # noqa: BLE001
        writer.write(coverage(engagement, run_id, "jenkins", account, region,
                              "jenkins:<what failed>", _reason(exc), str(exc)[:400],
                              lost="..."))
```

Then register it: `COLLECTORS["jenkins"] = collect_jenkins`,
`IMPLEMENTED.add("jenkins")`. `_reason()` is already in `handler.py` — reuse
it, don't write a second exception classifier.

## What to actually collect — unchanged from the original spec

`discovery`'s `tasks/P2-15.md` is still the exact behavioral reference.
Base URL `http://jenkins.condor.internal:8080`:

- **Controller**: version from the `X-Jenkins` response header; nodes and
  executors from `/computer/api/json`; plugins from
  `/pluginManager/api/json?depth=1` (short name, version, active).
- **Plugin advisories**: fetch
  `https://updates.jenkins.io/update-center.actual.json`, match installed
  versions against its `warnings` entries, one record per match. This is
  live evidence for `AK-PIP-10` — matrix-auth 3.2.9 has a real advisory,
  pinned on purpose (see `discovery`'s `estate/iac/jenkins/` for why).
- **Jobs**: `/api/json?tree=jobs[name,url,_class,jobs[name,url,_class]]`,
  recursive for multibranch. Pull `config.xml` per job.
- **Builds since checkpoint**: `number`, `result`, `timestamp`, `duration`,
  `causes`, SCM revision SHA from `actions` (`lastBuiltRevision`). There's
  no `ctx.checkpoint` helper here the way the old plan assumed — check
  `runtime/dp/` for an equivalent, or ask Alejandro whether checkpointing
  is handled by the run ledger (`dp-run-ledger` / DynamoDB) instead.
- **Credentials**: IDs, types, descriptions only — **never secret fields**.
  If the plugin won't expose even that without admin rights, emit
  `coverage` with `reason=access_denied` and move on.
- **Jenkinsfile**: for multibranch jobs, record which repo/branch backs it.
  Don't fetch file contents — the GitHub collector already has those.
- **Unreachable controller**: `coverage` with `reason=unreachable`,
  **succeed anyway**. A down Jenkins should never fail the whole run — this
  matters even more now that network reachability itself is an open
  question (see above): until it's resolved, this is the path your
  collector will actually take every time it's invoked.

Acceptance, concretely, once live: two jobs found;
`facturacion-nightly-export`'s `config.xml` present and contains
`ssm send-command` (the planted "no source repo, defined only in Jenkins"
finding, `AK-PIP-07`); at least one plugin warning matched; builds since
`history_start` present.

## Credentials

The old plan had a token at Secrets Manager path `dp/jenkins/reader`,
created by a task (`P2-04`) that never got built as such. Check whether
`ai-discovery-tool` already has an equivalent secret path wired (look in
`terraform/30-collect/iam.tf` and `client-grant/` for a Jenkins-shaped
credential grant) — if not, that's a real gap to raise, not something to
work around by hardcoding a token.

## What you can do before the network question is resolved

- Write `collect_jenkins` and register it — it'll just always take the
  `unreachable` coverage path until the network exists, which is correct,
  honest behavior, not a bug.
- Write offline unit tests with recorded JSON/XML fixtures — follow
  `runtime/tests/test_handlers.py`'s style. Pull real fixtures by hand
  (`curl` through an SSM tunnel — ask Diego for the access brief) so
  they're accurate to the real controller, not invented.
- Confirm empirically whether the credentials API exposes ID/type/
  description without admin rights, so you know now whether you'll be
  emitting `access_denied` coverage for that whole record kind later.

## Rules that still apply, unchanged

- **Read-only, no exceptions.** Never use the collector's own path to do
  anything that could be mistaken for a control action (triggering a
  build, etc.) — use your own access for that kind of poking around.
- **Never log or store a secret value.** Evidence is Object Lock-protected
  once written — there's no delete path — so redaction has to happen
  before `writer.write()`, never after.
- **Don't "fix" anything you find weird in the real Jenkins.** The
  outdated matrix-auth plugin, the admin-role-holding CodeBuild role, the
  no-approval-gate Reportes pipeline, the Jenkins-only nightly export with
  no backing repo — all planted, all intentional evidence your collector
  exists to surface. Check `discovery`'s `answer-key/answer-key.yaml`
  before assuming something's broken.

## Coordination

1. **The network question above is the real blocker — raise it early**,
   with Alejandro and Oscar both, since it likely affects Oscar's Aurora
   work too.
2. **Diego and Alejandro are splitting the other ~33 collectors** — confirm
   you're not duplicating effort, and that nobody else has started
   `jenkins` already.
3. Talk to Alejandro before your first PR regardless — he has context on
   the framework (like the checkpoint question above) that isn't fully
   written down yet.

## Testing

`make check` in `ai-discovery-tool` (fmt, validate, offline tests, policy)
— no AWS credentials needed for any of it except the parts you can't test
until the network question above is resolved.

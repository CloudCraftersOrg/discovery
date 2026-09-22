# Onboarding — Santiago, Jenkins discovery

Scope: `P2-15` (the Jenkins collector), plus enough of its neighbors
(`P2-16`'s `jenkinsfile`/`jenkins_config_xml` parsers, `P2-17`'s
source-traceability tests) to know what your output feeds into.

You're pulling **evidence about Jenkins**, from Jenkins — jobs, builds,
plugins, credential references — read-only, into the platform's raw
storage. You are not touching the Jenkins controller itself, and you are
not writing anything back to it.

## Before you write any code

1. Read `CLAUDE.md` in full, especially §4 ("the estate is a fixture,
   defects are intentional") and §9 ("things agents commonly get wrong
   here"). Two lines there are written almost exactly for your task:
   *"Treating the Jenkins controller or the GitHub runner as part of an
   application. They are shared platform tooling."* and *"Fixing a
   planted defect 'for security.' Breaks the answer key."*
2. Read `docs/ARCHITECTURE.md` — it has the real topology and the exact
   role Jenkins plays: CI for Tienda, Pagos and Reportes, plus
   Facturación's nightly export job. `docs/DISCOVERY-CHECKLIST.md` lists
   every answer-key item your collector is on the hook for as an evidence
   source (search it for `jenkins`).
3. `condor-jenkins` is real and running right now:
   `http://jenkins.condor.internal:8080`, inside `condor-vpc`. Nothing
   about it is simulated — the plugin versions, the credentials store,
   the job configs are genuine. Ask Diego for the access brief (AWS
   Identity Center invite + the SSM tunnel steps) so you can poke around
   in the real controller before writing the collector.

## Your task, exactly

`P2-15`, domain `pipelines`, base URL `http://jenkins.condor.internal:8080`,
auth token from Secrets Manager path `dp/jenkins/reader` (this gets
created by `P2-04`, owned by Oscar — **you're blocked on live testing
until that lands**, though nothing stops you writing the collector logic
and its offline unit tests first, see below).

What to collect:

- **Controller**: version from the `X-Jenkins` response header; nodes and
  executors from `/computer/api/json`; plugins from
  `/pluginManager/api/json?depth=1` (short name, version, active).
- **Plugin advisories**: fetch
  `https://updates.jenkins.io/update-center.actual.json` (through the
  platform's egress path, `P2-02` — not yours, but your Lambda's outbound
  traffic depends on it existing), match installed versions against its
  `warnings` entries, emit one `resource` record per match. This is the
  live evidence behind `AK-PIP-10` (matrix-auth 3.2.9 has a real
  advisory, pinned on purpose — see `estate/iac/jenkins/` for why).
- **Jobs**: `/api/json?tree=jobs[name,url,_class,jobs[name,url,_class]]`,
  recursive for multibranch. Pull `config.xml` per job.
- **Builds since checkpoint**: `number`, `result`, `timestamp`,
  `duration`, `causes`, and the SCM revision SHA out of `actions`
  (`lastBuiltRevision`). Use `ctx.checkpoint` (from the `dp_collect`
  framework, `P2-07`) so re-runs only pull new builds.
- **Credentials**: IDs, types, descriptions from the credentials API —
  **no secret fields, ever**. If the plugin won't expose even that
  without admin rights, emit a `coverage` record with
  `reason=access_denied` and move on; that's a valid, expected outcome,
  not a bug to work around.
- **Jenkinsfile**: for multibranch jobs, record which repo/branch backs
  it. Don't fetch file contents — the GitHub collector already has those.
- **Unreachable controller**: emit `coverage` with `reason=unreachable`
  and **succeed anyway**. A down Jenkins should never fail the whole
  collection cycle.

Acceptance, concretely: two jobs found; `facturacion-nightly-export`'s
`config.xml` present and contains `ssm send-command` (this is the
planted "no source repo, defined only in Jenkins" finding, `AK-PIP-07`);
at least one plugin warning matched; builds since `history_start` present.
Unit tests with recorded JSON/XML fixtures, including the unreachable
path.

## What you're blocked on, and what you can do meanwhile

`P2-15` formally depends on `P2-07` (the `dp_collect` collector
framework — base class, session/pagination/checkpoint helpers, the
redaction pipeline, the writer), `P2-03` (private network path to the
estate — already mostly solved by ADR-044, since there's one VPC now,
not a peered pair), `P2-02` (egress for the plugin-advisory fetch), and
`P2-04` (the `dp/jenkins/reader` token, owned by Oscar).

None of those are done yet (check `tasks/STATUS.md`). Until they are,
you can still make real progress:

- Read `tasks/P2-07.md` now — it defines the exact `Collector` base
  class interface (`domain`, `name`, `version`, `regional`, `collect(ctx)
  -> Iterator[Record]`) you'll subclass. Write against that interface
  even before the framework package exists; you'll wire it up once it
  lands.
- Hit Jenkins's real API by hand (`curl`, or a throwaway script) through
  an SSM tunnel to record realistic JSON/XML fixtures now — you don't
  need the collector framework to *look at* what the controller actually
  returns.
- Write the redaction-adjacent thinking now: the credentials API's shape,
  and confirm empirically whether it exposes ID/type/description without
  admin rights, or whether you'll be emitting `access_denied` coverage
  for that whole record kind.

## The one thing worth understanding early: `P2-16`

You're not building `P2-16` (it's a separate task, Product stream, not
yours), but it consumes your collector's raw output directly. Its
`jenkinsfile` and `jenkins_config_xml` parsers turn what you collect into
structured `DeployIntent` records — mechanism (`codedeploy`, `helm`,
`ssm_command`, …), credential mode, whether there's an approval gate.
They're **pattern-based, never evaluating Groovy** — a deliberate
constraint, not a shortcut: don't be tempted to make your own collector
smarter about parsing Jenkinsfile semantics, that logic belongs in
`P2-16`, over on the raw text you hand it. Your job stops at faithful,
complete, redacted evidence.

Estate fixtures `P2-16` is graded against, for context on what your
collector needs to make visible: Reportes should parse to `codedeploy`
with `instance_profile`, `has_approval=false`, `has_test_stage=false` —
that's the real, planted "no approval before deploy" finding
(`AK-PIP-06`). If your collector doesn't surface enough of the
Jenkinsfile/job structure for that to be derivable downstream, it's a gap
in `P2-15`, not `P2-16`.

## Rules that apply specifically to you

- **Read-only, no exceptions.** The `dp-collector` role literally cannot
  write to Jenkins (least-privilege by IAM, not by your own restraint) —
  but even reads that could be mistaken for control-plane actions (like
  triggering a build to see what happens) are out of scope. If you need
  to understand Jenkins's behavior, use your own testing/admin access —
  never the collector's.
- **Never log or store a secret value** — this one has an actual
  enforcement mechanism (`dp_collect.redact`, from `P2-07`): every
  detector runs across every string value in every record before it's
  written, and raw storage is Object Lock-protected, so a secret that
  slips through can never be deleted afterward. Treat that as the reason
  the credentials-API rule above is absolute, not just a guideline.
- **Don't "fix" anything you find weird in Jenkins.** The outdated
  matrix-auth plugin, the admin-role-holding CodeBuild role, the
  no-approval-gate Reportes pipeline, the Jenkins-only nightly export
  with no backing repo — all planted, all intentional, all things your
  collector exists to surface, not resolve. Check
  `answer-key/answer-key.yaml` before assuming something's broken.

## Definition of done (CLAUDE.md §8, same bar as every task)

Acceptance commands pass, output pasted in the PR. `ruff check`/
`ruff format --check` pass. No secret values anywhere — code, logs,
fixtures, PR text. `PLANTED:` markers referenced where relevant.
Answer-key items you touch (`AK-PIP-04`, `AK-PIP-06`, `AK-PIP-07`,
`AK-PIP-10`, `AK-DEP-03` at least) named by ID in the PR.
`tasks/STATUS.md` updated.

## Where things live

Your code: `platform/collectors/pipelines/jenkins/`. Fixtures:
`tests/fixtures/` under that path, JSON/XML, at least the two positive
cases plus the unreachable-controller case. Read `platform/collectors/README.md`
for the framework's general conventions once `P2-07` lands.

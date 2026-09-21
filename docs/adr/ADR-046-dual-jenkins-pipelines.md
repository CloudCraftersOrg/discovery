# ADR-046: Tienda and Pagos get a second, parallel Jenkins pipeline

## Status

Accepted.

## Context

The taskpack deliberately planted CI/CD diversity across apps (AK-PIP-01: Tienda via CodePipeline, Pagos via GitHub Actions, Reportes via Jenkins) as part of the discovery platform's test surface. The operator asked for every buildable app to also get a real Jenkins pipeline, explicitly alongside each app's existing one rather than replacing it — acknowledging up front that this duplicates Tienda's and Pagos' original deploy paths.

Inventario is excluded: P1-08 (its own task) is `blocked` — Tienda's GitHub CodeStarConnections OAuth handshake (P1-06, `tasks/HANDOFF-P1-06.md`) is still pending human action, so there's no registered app repo or working Jenkinsfile to build a job from yet. Facturación is excluded: it has no deployable app code (no buildspec/appspec/repo exists for it), so there's nothing for a pipeline to build.

## Decision

Tienda and Pagos each get a second multibranch Jenkins pipeline (`condor-jenkins-shared-library`-based `Jenkinsfile`s), running alongside — not replacing — their existing CodePipeline/GitHub Actions deploys. `AK-PIP-01`'s `expect.tienda` and `expect.pagos` moved from a single pipeline-technology string to a list, to capture both as true state.

## Consequences

- The discovery platform's pipeline-link collector must tolerate an app having more than one pipeline technology — this is real state now, not noise to filter.
- Tienda's Jenkins pipeline preserves the CodePipeline's manual-approval semantics (an `input` step before deploy, verified live); Pagos' does not, matching its GitHub Actions deploy's own lack of one.
- Both new pipelines deploy to the same targets as the originals (Tienda's CodeDeploy application/deployment group, Pagos' EKS cluster) — a real trigger from either pipeline is a real deploy in this account, not a dry run. Confirmed live for both: Tienda's ASG instances re-served `/health` after a Jenkins-triggered CodeDeploy, and Pagos' pods rolled out and reached `1/1 Running` after a Jenkins-triggered `helm upgrade`.
- Building both a commit's bare-SHA image tag (GitHub Actions) and a Jenkins-triggered rebuild of the same commit collide on Pagos' immutable-tag ECR repo — `condorEcrBuildPush` tags Jenkins builds `jenkins-<sha>` to avoid it.
- Inventario and Facturación are unaffected; `AK-PIP-02` (Inventario manual-deploy) and `AK-PIP-11` (Inventario/Facturación no-pipeline) still hold as originally planted.
- Future phases reading pipeline data (P2-17 collector-contract tests, P4-12 answer-key evaluation harness) must account for Tienda and Pagos each having two pipeline sources, not one.

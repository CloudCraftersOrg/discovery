# HANDOFF-P1-06 · CodeStarConnections GitHub handshake

Stack `condor-tienda` is `CREATE_COMPLETE`. Everything except the pipeline's
first run is live: ALB, 2× m5.large in the ASG (both `InService`/`Healthy`),
RDS `condor-tienda-db` (`available`), CloudWatch alarms, and the
CodePipeline — waiting at Source because the GitHub connection is `PENDING`.

**Steps, for whoever holds admin on `CloudCraftersOrg`:**

1. AWS Console → Developer Tools → Settings → Connections (region `us-east-1`).
2. Find `condor-tienda` (ARN `arn:aws:codestar-connections:us-east-1:337058058699:connection/f3f1d10f-0328-4055-8d51-ded5333da2f0`), status `Pending`.
3. Click **Update pending connection** → authorize the AWS Connector for GitHub app against `CloudCraftersOrg/condor-tienda` → complete the OAuth flow.
4. Status should flip to `Available` within a few seconds.

**After that, per the task's own acceptance criteria:**

- A push to `main` on `condor-tienda` runs the pipeline automatically (Source → Build → **Approve** → Deploy). It will sit at the manual approval action — that's intentional, not a hang.
- Approve it in the CodePipeline console to let CodeDeploy actually push to the ASG instances.
- Once deployed, `curl tienda.condor.internal/health` from inside the VPC (e.g. from the Jenkins/Pagos side, once those exist) should return `200`.

Until the connection is approved, the pipeline has never run and the ASG
instances are healthy at the infrastructure level only — no application code
is deployed to them yet, so `/health` won't respond until a deploy completes.

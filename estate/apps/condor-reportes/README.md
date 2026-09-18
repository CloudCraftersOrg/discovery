# condor-reportes

Mercado Cóndor's reporting service. Java 17, plain `HttpServer` (no
framework), running under systemd (`deploy/condor-reportes.service`),
deployed by the `Jenkinsfile` here through CodeDeploy (`appspec.yml`,
`scripts/`) — no approval gate before deploy (PLANTED: AK-PIP-06).

- `GET /report` — a fixed-shape JSON status payload.

## Test

```
mvn test
```

Create a file named `FAIL_BUILD` at the repo root to force the build to fail.

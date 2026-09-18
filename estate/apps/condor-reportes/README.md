# condor-reportes

Mercado Cóndor's reporting service. Java 17, plain `HttpServer` (no
framework), deployed via systemd unit (`deploy/condor-reportes.service`),
built and deployed by the `Jenkinsfile` here.

- `GET /report` — a fixed-shape JSON status payload.

## Test

```
mvn test
```

Create a file named `FAIL_BUILD` at the repo root to force the build to fail.

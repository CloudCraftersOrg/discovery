# condor-pagos

Mercado Cóndor's payments service. Node.js (Active LTS) + Express, deployed
to EKS via the Helm chart in `chart/` (task P1-07). State in MySQL
(`payments` table).

- `GET /health`
- `POST /pay` `{order_id, amount}` — writes `payments`, called by Tienda's
  `/checkout`.

## Test

```
npm install
npm test
```

Create a file named `FAIL_BUILD` at the repo root to force the build to fail.

## Container

```
docker build -t condor-pagos .
```

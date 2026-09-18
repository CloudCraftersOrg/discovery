# condor-tienda

Mercado Cóndor's storefront. Flask + gunicorn, deployed via systemd unit
(`deploy/condor-tienda.service`), state in PostgreSQL (`orders` table).

- `GET /health`
- `GET /checkout?amount=<n>` — writes `orders`, calls Pagos at
  `PAGOS_URL` (default `http://pagos.condor.internal/pay`), updates the
  order's status with the result.

## Test

```
pip install -r requirements.txt -r requirements-dev.txt
pytest
```

Create a file named `FAIL_BUILD` at the repo root to force the build to fail.

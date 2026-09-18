# condor-inventario

Reads Tienda's `orders` table every `INTERVAL_SECONDS` (default 300) and
logs the count. Runs as an ECS Fargate task (task P1-08), no HTTP surface.

## Test

```
pip install -r requirements.txt -r requirements-dev.txt
pytest
```

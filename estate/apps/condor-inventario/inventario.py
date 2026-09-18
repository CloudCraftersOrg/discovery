import logging
import os
import time

import psycopg2

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
log = logging.getLogger("condor-inventario")

DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://tienda@localhost/tienda")
INTERVAL_SECONDS = int(os.environ.get("INTERVAL_SECONDS", "300"))


def count_orders():
    conn = psycopg2.connect(DATABASE_URL)
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT count(*) FROM orders")
            return cur.fetchone()[0]
    finally:
        conn.close()


def run_forever():
    while True:
        try:
            log.info("orders count: %s", count_orders())
        except Exception:
            log.exception("failed to count orders")
        time.sleep(INTERVAL_SECONDS)


if __name__ == "__main__":
    run_forever()

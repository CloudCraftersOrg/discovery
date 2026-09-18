import os
import uuid

import psycopg2
import requests
from flask import Flask, jsonify, request

app = Flask(__name__)

PAGOS_URL = os.environ.get("PAGOS_URL", "http://pagos.condor.internal/pay")
DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://tienda@localhost/tienda")


def get_connection():
    return psycopg2.connect(DATABASE_URL)


@app.get("/health")
def health():
    return jsonify(status="ok"), 200


@app.get("/checkout")
def checkout():
    order_id = str(uuid.uuid4())
    amount = request.args.get("amount", "0")

    conn = get_connection()
    try:
        with conn, conn.cursor() as cur:
            cur.execute(
                "INSERT INTO orders (id, amount, status) VALUES (%s, %s, %s)",
                (order_id, amount, "pending"),
            )
    finally:
        conn.close()

    payment = requests.post(PAGOS_URL, json={"order_id": order_id, "amount": amount}, timeout=5)

    conn = get_connection()
    try:
        with conn, conn.cursor() as cur:
            cur.execute(
                "UPDATE orders SET status = %s WHERE id = %s",
                ("paid" if payment.ok else "failed", order_id),
            )
    finally:
        conn.close()

    return jsonify(order_id=order_id, paid=payment.ok), 200 if payment.ok else 502


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)

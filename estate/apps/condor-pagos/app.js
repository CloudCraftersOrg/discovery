const express = require("express");
const mysql = require("mysql2/promise");

const app = express();
app.use(express.json());

const pool = mysql.createPool(
  process.env.DATABASE_URL || "mysql://pagos@localhost/pagos"
);

app.get("/health", (_req, res) => {
  res.json({ status: "ok" });
});

app.post("/pay", async (req, res) => {
  const { order_id: orderId, amount } = req.body || {};
  if (!orderId || amount === undefined) {
    return res.status(400).json({ error: "order_id and amount are required" });
  }

  try {
    await pool.query(
      "INSERT INTO payments (order_id, amount, status) VALUES (?, ?, ?)",
      [orderId, amount, "settled"]
    );
    return res.json({ order_id: orderId, status: "settled" });
  } catch (err) {
    return res.status(502).json({ error: err.message });
  }
});

if (require.main === module) {
  const port = process.env.PORT || 8080;
  app.listen(port, () => {
    // eslint-disable-next-line no-console
    console.log(`condor-pagos listening on ${port}`);
  });
}

module.exports = app;

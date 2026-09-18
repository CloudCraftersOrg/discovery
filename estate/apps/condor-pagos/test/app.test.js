const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");
const request = require("supertest");
const app = require("../app");

test("GET /health", async () => {
  const res = await request(app).get("/health");
  assert.strictEqual(res.status, 200);
  assert.strictEqual(res.body.status, "ok");
});

test("build is not forced to fail", () => {
  const marker = path.join(__dirname, "..", "FAIL_BUILD");
  assert.strictEqual(fs.existsSync(marker), false);
});

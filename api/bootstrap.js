const fs = require("node:fs");
const path = require("node:path");

module.exports = function handler(_req, res) {
  const bootstrapPath = path.join(process.cwd(), "bootstrap.sh");
  const script = fs.readFileSync(bootstrapPath, "utf8");

  res.setHeader("Content-Type", "text/plain; charset=utf-8");
  res.setHeader("Cache-Control", "s-maxage=60, stale-while-revalidate=300");
  res.status(200).send(script);
};
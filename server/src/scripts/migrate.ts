// Applies db/migrations/*.sql in order, skipping ones already applied. Usage: npm run db:migrate

import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { pool, transaction } from "../db/pool.ts";

const MIGRATIONS_DIR = join(import.meta.dirname, "../../db/migrations");

await pool.query(`CREATE TABLE IF NOT EXISTS schema_migrations (
  name TEXT PRIMARY KEY,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
)`);

const applied = new Set((await pool.query<{ name: string }>("SELECT name FROM schema_migrations")).rows.map((r) => r.name));
const pending = readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith(".sql") && !applied.has(f)).sort();

for (const name of pending) {
  await transaction(async (client) => {
    await client.query(readFileSync(join(MIGRATIONS_DIR, name), "utf8"));
    await client.query("INSERT INTO schema_migrations (name) VALUES ($1)", [name]);
  });
  console.log(`applied ${name}`);
}
console.log(pending.length ? "done" : "up to date");
await pool.end();

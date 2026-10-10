import { createHash, randomBytes } from "node:crypto";
import type pg from "pg";
import { pool } from "../db/pool.ts";

// A session token is 32 random bytes sent to the client once. We keep only its hash.

const SESSION_DAYS = 30;

/** The logged-in trainer, as rooms and HTTP routes see it. Ids are strings (Postgres BIGINT). */
export interface SessionTrainer {
  accountId: string;
  trainerId: string;
  name: string;
  mapId: string;
  x: number;
  y: number;
  facing: string;
  appearance: object | null; // null until character creation
  flags: Record<string, unknown>; // story progress, e.g. { intro: true }
}

const hashToken = (token: string) => createHash("sha256").update(token).digest();

export async function createSession(accountId: string, db: pg.Pool | pg.PoolClient = pool): Promise<string> {
  const token = randomBytes(32).toString("base64url");
  await db.query(
    `INSERT INTO sessions (token_hash, account_id, expires_at) VALUES ($1, $2, now() + make_interval(days => $3))`,
    [hashToken(token), accountId, SESSION_DAYS],
  );
  return token;
}

export async function findSession(token: unknown): Promise<SessionTrainer | null> {
  if (typeof token !== "string" || token.length < 20 || token.length > 100) return null;
  const { rows } = await pool.query(
    `SELECT t.account_id, t.id, t.name, t.map_id, t.x, t.y, t.facing, t.appearance, t.flags
       FROM sessions s JOIN trainers t ON t.account_id = s.account_id
      WHERE s.token_hash = $1 AND s.expires_at > now()`,
    [hashToken(token)],
  );
  const r = rows[0];
  if (!r) return null;
  return {
    accountId: r.account_id, trainerId: r.id, name: r.name, mapId: r.map_id,
    x: r.x, y: r.y, facing: r.facing, appearance: r.appearance, flags: r.flags ?? {},
  };
}

export async function deleteSession(token: string): Promise<void> {
  await pool.query("DELETE FROM sessions WHERE token_hash = $1", [hashToken(token)]);
}

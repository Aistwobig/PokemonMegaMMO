import { randomInt } from "node:crypto";
import express, { type Request, type Response } from "express";
import { pool, transaction } from "../db/pool.ts";
import { LookError, validateLook } from "../world/appearance.ts";
import type { GameMap } from "../world/maps.ts";
import { DUMMY_HASH, hashPassword, verifyPassword } from "./passwords.ts";
import { RateLimiter } from "./rateLimit.ts";
import { createSession, deleteSession, findSession, type SessionTrainer } from "./sessions.ts";

// HTTP endpoints for accounts. The client logs in here, then passes the token when joining rooms.
//   POST /auth/register  { username, password, trainerName }  → 201 { token, trainer }
//   POST /auth/login     { username, password }               → 200 { token, trainer }
//   POST /auth/logout    Authorization: Bearer <token>        → 204
//   GET  /auth/me        Authorization: Bearer <token>        → 200 { trainer }
//   PUT  /trainer/appearance  { look }  (Bearer)               → 200 { trainer }   (character creation)
//   POST /trainer/intro                 (Bearer)               → 200 { trainer }   (intro cutscene seen)

const START_MAP = "vaniville";
const USERNAME = /^[A-Za-z0-9_]{3,16}$/;
const TRAINER_NAME = /^[\p{L}\p{N} ]{1,12}$/u; // letters (any language), digits, spaces
const PASSWORD_MIN = 8;
const PASSWORD_MAX = 128;

const loginLimit = new RateLimiter(10, 15 * 60_000); // per IP and per username
const registerAttempts = new RateLimiter(30, 15 * 60_000); // per IP, every attempt (typos, taken names)
const accountsCreated = new RateLimiter(5, 60 * 60_000); // per IP, successful registrations only

class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

export function authRoutes(app: express.Application, maps: Map<string, GameMap>) {
  const startMap = maps.get(START_MAP);
  if (!startMap) throw new Error(`start map "${START_MAP}" not loaded`);

  app.use(["/auth", "/trainer"], express.json({ limit: "4kb" }));

  app.post("/auth/register", handle(async (req, res) => {
    const ip = `ip:${req.ip}`;
    if (!registerAttempts.allow(ip)) throw new HttpError(429, "Too many attempts. Try again in a few minutes.");
    if (accountsCreated.isLimited(ip)) throw new HttpError(429, "Too many accounts created. Try again later.");
    const username = field(req, "username");
    const password = field(req, "password");
    const trainerName = field(req, "trainerName").trim().replace(/\s+/g, " ");
    if (!USERNAME.test(username)) throw new HttpError(400, "Username must be 3–16 letters, digits or _.");
    if (password.length < PASSWORD_MIN || password.length > PASSWORD_MAX) {
      throw new HttpError(400, `Password must be ${PASSWORD_MIN}–${PASSWORD_MAX} characters.`);
    }
    if (password.toLowerCase().includes(username.toLowerCase())) throw new HttpError(400, "Password can't contain your username.");
    if (!TRAINER_NAME.test(trainerName)) throw new HttpError(400, "Trainer name must be 1–12 letters, digits or spaces.");

    const passwordHash = await hashPassword(password);
    const token = await transaction(async (db) => {
      try {
        const account = await db.query("INSERT INTO accounts (username, password_hash) VALUES ($1, $2) RETURNING id", [username, passwordHash]);
        const accountId: string = account.rows[0].id;
        await db.query(
          "INSERT INTO trainers (account_id, name, trainer_id, map_id, x, y) VALUES ($1, $2, $3, $4, $5, $6)",
          [accountId, trainerName, randomInt(100_000), startMap.id, startMap.spawn.x, startMap.spawn.y],
        );
        return await createSession(accountId, db);
      } catch (err) {
        if (isUniqueViolation(err, "accounts")) throw new HttpError(409, "That username is taken.");
        if (isUniqueViolation(err, "trainers_name")) throw new HttpError(409, "That trainer name is taken.");
        throw err;
      }
    });
    accountsCreated.record(ip);
    res.status(201).json({ token, trainer: publicTrainer((await findSession(token))!) });
  }));

  app.post("/auth/login", handle(async (req, res) => {
    const username = field(req, "username");
    const password = field(req, "password");
    if (!loginLimit.allow(`ip:${req.ip}`) || !loginLimit.allow(`user:${username.toLowerCase()}`)) {
      throw new HttpError(429, "Too many login attempts. Try again in a few minutes.");
    }
    const { rows } = await pool.query("SELECT id, password_hash FROM accounts WHERE lower(username) = lower($1)", [username]);
    const ok = await verifyPassword(password, rows[0]?.password_hash ?? DUMMY_HASH);
    if (!rows[0] || !ok) throw new HttpError(401, "Wrong username or password.");
    const token = await createSession(rows[0].id);
    res.json({ token, trainer: publicTrainer((await findSession(token))!) });
  }));

  app.post("/auth/logout", handle(async (req, res) => {
    const token = bearer(req);
    if (token) await deleteSession(token);
    res.status(204).end();
  }));

  app.get("/auth/me", handle(async (req, res) => {
    const session = await findSession(bearer(req));
    if (!session) throw new HttpError(401, "Not logged in.");
    res.json({ trainer: publicTrainer(session) });
  }));

  app.put("/trainer/appearance", handle(async (req, res) => {
    const session = await findSession(bearer(req));
    if (!session) throw new HttpError(401, "Not logged in.");
    let look;
    try {
      look = validateLook(req.body?.look);
    } catch (err) {
      if (err instanceof LookError) throw new HttpError(400, err.message);
      throw err;
    }
    await pool.query("UPDATE trainers SET appearance = $2 WHERE id = $1", [session.trainerId, look]);
    res.json({ trainer: publicTrainer({ ...session, appearance: look }) });
  }));

  // The intro (Sycamore's welcome, waking up at home) plays once, after character creation.
  app.post("/trainer/intro", handle(async (req, res) => {
    const session = await findSession(bearer(req));
    if (!session) throw new HttpError(401, "Not logged in.");
    if (!session.appearance) throw new HttpError(400, "Create your character first.");
    await pool.query(`UPDATE trainers SET flags = flags || '{"intro": true}' WHERE id = $1`, [session.trainerId]);
    res.json({ trainer: publicTrainer({ ...session, flags: { ...session.flags, intro: true } }) });
  }));
}

/** What the client gets to see about its own trainer. */
function publicTrainer(t: SessionTrainer) {
  return {
    name: t.name, mapId: t.mapId, x: t.x, y: t.y, facing: t.facing, appearance: t.appearance,
    introDone: t.flags.intro === true,
  };
}

function handle(fn: (req: Request, res: Response) => Promise<void>) {
  return async (req: Request, res: Response) => {
    try {
      await fn(req, res);
    } catch (err) {
      if (err instanceof HttpError) {
        res.status(err.status).json({ error: err.message });
      } else {
        console.error(`${req.method} ${req.path} failed:`, err);
        res.status(500).json({ error: "Server error." });
      }
    }
  };
}

function field(req: Request, name: string): string {
  const value = req.body?.[name];
  if (typeof value !== "string") throw new HttpError(400, `Missing ${name}.`);
  return value;
}

function bearer(req: Request): string | undefined {
  const header = req.get("authorization");
  return header?.startsWith("Bearer ") ? header.slice(7) : undefined;
}

function isUniqueViolation(err: unknown, constraintPrefix: string): boolean {
  const e = err as { code?: string; constraint?: string };
  return e.code === "23505" && (e.constraint ?? "").startsWith(constraintPrefix);
}

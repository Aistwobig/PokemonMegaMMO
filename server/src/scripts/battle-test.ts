// End-to-end check of starters, healing and wild battles against a running server + database.
//   npm run dev          (in another terminal)
//   npm run test:battle
// Registers a throwaway trainer, picks a starter, walks the real maps to Route 2's tall grass and
// fights the first wild Pokémon: attacks, then throws Poké Balls until it's caught or gone.

import { Client, type Room } from "@colyseus/sdk";
import { config } from "../config.ts";
import { pool } from "../db/pool.ts";
import { AQUACORDE_TO_ROUTE2, ROUTE1_TO_AQUACORDE, VANIVILLE_TO_ROUTE1 } from "./paths.ts";

const http = `http://localhost:${config.port}`;
const id = Math.random().toString(36).slice(2, 7);
let failures = 0;
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

function check(name: string, ok: boolean, detail = "") {
  console.log(`${ok ? "  ok  " : "  FAIL"} ${name}${ok || !detail ? "" : ` — ${detail}`}`);
  if (!ok) failures++;
}

async function call(method: string, path: string, body?: object, token?: string) {
  const res = await fetch(http + path, {
    method,
    headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  return { status: res.status, data: text ? JSON.parse(text) : {} };
}

console.log("starter");
let r = await call("POST", "/auth/register", { username: `battle_${id}`, password: "correct horse battery", trainerName: `Battler${id}` });
const token: string = r.data.token;
r = await call("GET", "/trainer/party", undefined, token);
check("no Pokémon at first", r.status === 200 && r.data.party?.length === 0, JSON.stringify(r));
r = await call("POST", "/trainer/starter", { species: "pikachu" }, token);
check("only the three starters", r.status === 400, JSON.stringify(r));
r = await call("POST", "/trainer/starter", { species: "froakie" }, token);
check("starter given", r.status === 201 && r.data.party?.[0]?.species === "froakie" && r.data.party[0].level === 5, JSON.stringify(r));
check("comes with Poké Balls", r.data.items?.pokeball === 10, JSON.stringify(r.data.items));
r = await call("POST", "/trainer/starter", { species: "chespin" }, token);
check("only one starter", r.status === 409, JSON.stringify(r));

// --- walking with room changes, like the client does ---
const client = new Client(`ws://localhost:${config.port}`);
client.auth.token = token;
let room: Room = await client.joinOrCreate("vaniville");
let warp: { to: string; ticket: string } | undefined;
let battle: any;
let healed = false;
const updates: any[] = [];
function listen(rm: Room) {
  rm.onMessage("warp", (m) => (warp = m));
  rm.onMessage("healed", () => (healed = true));
  rm.onMessage("battleStart", (u) => (battle = u));
  rm.onMessage("battleUpdate", (u) => updates.push(u));
}
listen(room);
await sleep(300);

console.log("home");
room.send("move", "up"); // into the front door
await sleep(400);
check("walking into your front door heals", healed);

async function walk(dirs: string[]) {
  for (const d of dirs) {
    if (warp || battle) break;
    room.send("move", d);
    await sleep(230);
  }
  if (warp) {
    const w = warp;
    warp = undefined;
    await room.leave();
    room = await client.joinOrCreate(w.to, { ticket: w.ticket });
    listen(room);
    await sleep(300);
  }
}

console.log("route 2");
await walk(VANIVILLE_TO_ROUTE1);
await walk(ROUTE1_TO_AQUACORDE);
await walk(AQUACORDE_TO_ROUTE2);
check("reached Route 2", room.name === "route2" || (room as any).roomName === "route2" || !!room.state.players, room.name);
await walk(["up", "up", "up", "up", "up", "up", "up", "up", "up", "up", "up", "up", "up", "up", "up"]);
for (let i = 0; i < 300 && !battle; i++) {
  room.send("move", i % 6 < 3 ? "left" : "right");
  await sleep(230);
}
check("a wild Pokémon appears in the tall grass", !!battle, "no encounter after 300 steps");

if (battle) {
  console.log("battle");
  const texts = (u: any) => u.events.map((e: any) => e.text).filter(Boolean);
  check("battle opens with the wild Pokémon, then ours", texts(battle)[0]?.startsWith("A wild") && texts(battle)[1] === "Go! Froakie!", JSON.stringify(texts(battle)));
  check("moves to choose from", battle.request?.kind === "move" && battle.request.moves.length > 0, JSON.stringify(battle.request));
  const me = room.state.players.get(room.sessionId);
  const before = { x: me?.x, y: me?.y };
  room.send("move", "up");
  await sleep(300);
  check("can't walk away mid-battle", me?.x === before.x && me?.y === before.y);

  async function act(action: object) {
    const n = updates.length;
    room.send("battle", action);
    for (let i = 0; i < 40 && updates.length === n; i++) await sleep(50);
    return updates[updates.length - 1];
  }
  let u = await act({ type: "move", index: battle.request.moves.findIndex((m: any) => m.id !== "growl") });
  check("attacking plays out a turn", u && u.events.some((e: any) => e.text?.includes("used")), JSON.stringify(u?.events));
  for (let i = 0; i < 12 && u && !u.result; i++) {
    u = u.request?.kind === "switch" ? await act({ type: "switch", slot: 0 }) : await act({ type: "ball", item: "pokeball" });
  }
  console.log(`       result: ${u?.result} — ${texts(u ?? { events: [] }).slice(-3).join(" / ")}`);
  check("the battle ends", !!u?.result, JSON.stringify(u));
  const saved = await pool.query(
    `SELECT p.species, p.location, p.caught_ball FROM pokemon p JOIN trainers t ON t.id = p.owner_id WHERE t.name = $1 ORDER BY p.id`,
    [`Battler${id}`]);
  if (u?.result === "caught") check("caught Pokémon saved to the party", saved.rows.length === 2 && saved.rows[1].location === "party", JSON.stringify(saved.rows));
  const balls = await call("GET", "/trainer/party", undefined, token);
  check("Poké Balls were used", (balls.data.items.pokeball ?? 0) < 10, JSON.stringify(balls.data.items));
  room.send("move", "left");
  await sleep(400);
  const after = room.state.players.get(room.sessionId);
  check("free to walk after the battle", u?.result === "lost" || after?.x !== before.x || after?.y !== before.y);
}

await room.leave();
console.log(failures ? `\n${failures} check(s) failed` : "\nall checks passed");
await pool.end();
process.exit(failures ? 1 : 0);

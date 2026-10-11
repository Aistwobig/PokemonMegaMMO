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
let npcs: any[] = [];
let battlesStarted = 0;
let healed = false;
const updates: any[] = [];
function listen(rm: Room) {
  rm.onMessage("warp", (m) => (warp = m));
  rm.onMessage("healed", () => (healed = true));
  rm.onMessage("battleStart", (u) => { battle = u; battlesStarted++; });
  rm.onMessage("battleUpdate", (u) => updates.push(u));
  rm.onMessage("npcs", (n) => (npcs = n));
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
  if (u?.result === "caught") {
    const swapped = await call("POST", "/trainer/party/swap", { a: 0, b: 1 }, token);
    check("party reorders", swapped.status === 200 && swapped.data.party[0].species !== "froakie" && swapped.data.party[1].species === "froakie", JSON.stringify(swapped.data.party?.map((p: any) => p.species)));
    const bad = await call("POST", "/trainer/party/swap", { a: 0, b: 5 }, token);
    check("can't swap with an empty slot", bad.status === 400, JSON.stringify(bad));
  }
  room.send("move", "left");
  await sleep(400);
  const after = room.state.players.get(room.sessionId);
  check("free to walk after the battle", u?.result === "lost" || after?.x !== before.x || after?.y !== before.y);
}

console.log("trainer");
check("the map's trainers are sent on join", npcs.some((n) => n.id === "anna" && n.className === "Lass" && !n.beaten), JSON.stringify(npcs));
async function act(action: object) {
  const n = updates.length;
  room.send("battle", action);
  for (let i = 0; i < 40 && updates.length === n; i++) await sleep(50);
  return updates[updates.length - 1];
}
/** Plays a battle to the end: runs from wild Pokémon, attacks trainers' (switching if forced). */
async function finish(start: any) {
  let u = start;
  for (let i = 0; i < 40 && u && !u.result; i++) {
    if (u.request?.kind === "switch") {
      const next = u.view.party.find((p: any) => p.hp > 0);
      u = await act({ type: "switch", slot: next.slot });
    } else if (!start.trainer && !start.view.trainer) u = await act({ type: "run" });
    else u = await act({ type: "move", index: u.request.moves.findIndex((m: any) => !["growl", "leer", "tailwhip"].includes(m.id)) });
  }
  return u;
}
// Up to Lass Anna's row (Route 2 row 16; she looks right from (16, 16)).
let trainerBattle: any;
for (let i = 0; i < 120 && !trainerBattle; i++) { // generous: wild encounters in the grass on the way
  const me = room.state.players.get(room.sessionId)!;
  const seen = battlesStarted;
  const dir = me.x < 20 ? "right" : me.x > 20 ? "left" : "up";
  room.send("move", dir);
  await sleep(260);
  for (let w = 0; w < 10 && battlesStarted === seen; w++) await sleep(50); // a start can arrive late
  if (battlesStarted !== seen) {
    if (battle.trainer) trainerBattle = battle;
    else await finish(battle);
  }
}
const at = room.state.players.get(room.sessionId);
check("Lass Anna spots the player", trainerBattle?.trainer?.id === "anna", `in ${room.name} at (${at?.x}, ${at?.y})`);
if (trainerBattle) {
  const texts = trainerBattle.events.map((e: any) => e.text).filter(Boolean);
  check("trainer battle opens with the challenge", texts[0] === "You are challenged by Lass Anna!" && texts[1] === "Lass Anna sent out Pikachu!", JSON.stringify(texts));
  const nope = await act({ type: "ball", item: "pokeball" });
  check("can't catch a trainer's Pokémon", nope.events.some((e: any) => e.text === "Don't be a thief!"), JSON.stringify(nope.events));
  const run = await act({ type: "run" });
  check("can't run from a trainer", run.events.some((e: any) => e.text?.includes("no running")), JSON.stringify(run.events));
  const end = await finish(trainerBattle);
  console.log(`       result: ${end?.result} — ${end?.events.map((e: any) => e.text).filter(Boolean).slice(-3).join(" / ")}`);
  check("trainer battle ends", !!end?.result, JSON.stringify(end));
  if (end?.result === "win") {
    const p = await call("GET", "/trainer/party", undefined, token);
    check("prize money paid", p.data.money === 120, JSON.stringify(p.data.money));
    battle = undefined;
    room.send("move", "down");
    await sleep(300);
    room.send("move", "up");
    await sleep(400);
    check("a beaten trainer doesn't battle again", !battle?.trainer, JSON.stringify(battle?.trainer));
  }
}

await room.leave();
console.log(failures ? `\n${failures} check(s) failed` : "\nall checks passed");
await pool.end();
process.exit(failures ? 1 : 0);

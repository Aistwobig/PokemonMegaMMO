// A headless test player. Registers (or logs in), then walks from wherever its trainer is saved
// toward Route 2 and into the grass, following warps the way the real client will.
// Start the server first, then:
//   npm run bot -- Ash
//   npm run bot -- Ash --wander 60     walk around the current map at random for 60 seconds
// Run two at once to see them notice each other.

import { Client, type Room } from "@colyseus/sdk";
import { config } from "../config.ts";
import { AQUACORDE_TO_ROUTE2, ROUTE1_TO_AQUACORDE, ROUTE2_GRASS, VANIVILLE_TO_ROUTE1 } from "./paths.ts";

const name = process.argv[2] ?? "Bot";
const password = `bot-password-${name.length}`; // test accounts only
const http = `http://localhost:${config.port}`;
const client = new Client(`ws://localhost:${config.port}`);

async function post(path: string, body: object): Promise<{ status: number; data: any }> {
  const res = await fetch(http + path, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
  return { status: res.status, data: await res.json() };
}

/** Logs in, registering the account on first run. Returns the map the trainer is saved on. */
async function login(): Promise<string> {
  let res = await post("/auth/login", { username: name, password });
  if (res.status === 401) res = await post("/auth/register", { username: name, password, trainerName: name });
  if (!res.data.token) throw new Error(`login failed: ${res.data.error}`);
  client.auth.token = res.data.token;
  console.log(`[${name}] logged in, trainer saved in ${res.data.trainer.mapId}`);
  return res.data.trainer.mapId;
}

// Directions to walk in each map until the next warp (see paths.ts).
const ROUTE: Record<string, string[]> = {
  vaniville: VANIVILLE_TO_ROUTE1,
  route1: ROUTE1_TO_AQUACORDE,
  aquacorde: AQUACORDE_TO_ROUTE2,
  route2: ROUTE2_GRASS,
};

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function visit(mapId: string, ticket?: string): Promise<void> {
  const room: Room = await client.joinOrCreate(mapId, { ticket });
  let next: { to: string; ticket: string } | undefined;
  let encountered = false;

  room.onMessage("warp", (msg) => (next = msg));
  room.onMessage("wildEncounter", (wild) => {
    encountered = true;
    console.log(`[${name}] a wild ${wild.species} (Lv. ${wild.level}) appeared!`);
  });

  await sleep(300); // let the first state sync arrive
  const others = [...room.state.players.values()].filter((p: any) => p.name !== name).map((p: any) => p.name);
  const me = room.state.players.get(room.sessionId);
  console.log(`[${name}] in ${mapId} at (${me?.x}, ${me?.y})${others.length ? `, also here: ${others.join(", ")}` : ""}`);

  for (const dir of ROUTE[mapId] ?? []) {
    if (next || encountered) break;
    room.send("move", dir);
    await sleep(250);
  }

  await room.leave();
  if (next) return visit(next.to, next.ticket);
  if (!encountered) console.log(`[${name}] walked the whole route without an encounter`);
}

/** Random walk on one map, avoiding warps, so other clients have someone to watch. */
async function wander(mapId: string, seconds: number): Promise<void> {
  const room: Room = await client.joinOrCreate(mapId, {});
  let warped = false;
  room.onMessage("warp", () => (warped = true));
  room.onMessage("wildEncounter", () => room.send("battleEnd"));
  console.log(`[${name}] wandering ${mapId} for ${seconds}s`);
  await sleep(300); // let the first state sync arrive
  const dirs = ["up", "down", "left", "right"];
  let dir = "down";
  const until = Date.now() + seconds * 1000;
  while (Date.now() < until && !warped) {
    if (Math.random() < 0.3) dir = dirs[Math.floor(Math.random() * 4)];
    if (dir === "up" && (room.state.players?.get(room.sessionId)?.y ?? 99) <= 2) dir = "down"; // stay off the exit
    room.send("move", dir);
    await sleep(Math.random() < 0.2 ? 900 : 260);
  }
  await room.leave();
}

const mapId = await login();
const wanderAt = process.argv.indexOf("--wander");
if (wanderAt > 0) await wander(mapId, Number(process.argv[wanderAt + 1] ?? 30));
else await visit(mapId);
process.exit(0);

// End-to-end check of accounts and room login against a running server + database.
//   npm run dev          (in another terminal)
//   npm run test:auth
// Creates throwaway accounts with a random suffix, so it can run repeatedly.

import { Client, type Room } from "@colyseus/sdk";
import { config } from "../config.ts";
import { pool } from "../db/pool.ts";
import { VANIVILLE_TO_ROUTE1 } from "./paths.ts";

const http = `http://localhost:${config.port}`;
const ws = `ws://localhost:${config.port}`;
const id = Math.random().toString(36).slice(2, 7);
const user = `test_${id}`;
const password = "correct horse battery";
let failures = 0;

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

async function join(token: string | undefined, mapId: string, options: object = {}): Promise<Room | string> {
  const client = new Client(ws);
  if (token) client.auth.token = token;
  try {
    return await client.joinOrCreate(mapId, options);
  } catch (err: any) {
    return `${err.code ?? "?"} ${err.message}`;
  }
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

console.log("register");
let r = await call("POST", "/auth/register", { username: "ab", password, trainerName: "X" });
check("rejects short username", r.status === 400, JSON.stringify(r));
r = await call("POST", "/auth/register", { username: user, password: "short", trainerName: "X" });
check("rejects short password", r.status === 400, JSON.stringify(r));
r = await call("POST", "/auth/register", { username: user, password, trainerName: "<script>" });
check("rejects odd trainer names", r.status === 400, JSON.stringify(r));
r = await call("POST", "/auth/register", { username: user, password, trainerName: `Ash${id}` });
check("creates account", r.status === 201 && typeof r.data.token === "string", JSON.stringify(r));
check("trainer starts in vaniville", r.data.trainer?.mapId === "vaniville", JSON.stringify(r.data));
const firstToken: string = r.data.token;
r = await call("POST", "/auth/register", { username: user.toUpperCase(), password, trainerName: `Other${id}` });
check("username taken (any case)", r.status === 409, JSON.stringify(r));
r = await call("POST", "/auth/register", { username: `${user}b`, password, trainerName: `ash${id}` });
check("trainer name taken (any case)", r.status === 409, JSON.stringify(r));

console.log("login");
r = await call("POST", "/auth/login", { username: user, password: "wrong password!" });
check("wrong password → 401", r.status === 401, JSON.stringify(r));
r = await call("POST", "/auth/login", { username: `nobody_${id}`, password });
check("unknown user → same 401", r.status === 401 && r.data.error === "Wrong username or password.", JSON.stringify(r));
r = await call("POST", "/auth/login", { username: user.toUpperCase(), password });
check("login works (any case)", r.status === 200 && typeof r.data.token === "string", JSON.stringify(r));
const token: string = r.data.token;
r = await call("GET", "/auth/me", undefined, token);
check("/auth/me returns the trainer", r.status === 200 && r.data.trainer?.name === `Ash${id}`, JSON.stringify(r));
const stored = await pool.query("SELECT password_hash FROM accounts WHERE username = $1", [user]);
check("password stored hashed", stored.rows[0]?.password_hash.startsWith("scrypt$") && !stored.rows[0].password_hash.includes(password));

console.log("rooms");
let room = await join(undefined, "vaniville");
check("no token → refused", typeof room === "string", String(room));
room = await join("not-a-real-token-at-all-xxxx", "vaniville");
check("bad token → refused", typeof room === "string", String(room));
room = await join(token, "route2");
check("wrong map → refused", typeof room === "string" && room.includes("vaniville"), String(room));
room = await join(token, "route2", { ticket: "made-up-ticket" });
check("fake warp ticket → refused", typeof room === "string", String(room));
const first = await join(token, "vaniville");
check("own map → joined", typeof first !== "string", String(first));

if (typeof first !== "string") {
  await sleep(300);
  const me = first.state.players.get(first.sessionId);
  check("name comes from the database", me?.name === `Ash${id}`, JSON.stringify(me));

  let kicked: number | undefined;
  first.onLeave((code) => (kicked = code));
  const second = await join(firstToken, "vaniville"); // same trainer, older token
  await sleep(500);
  check("second login kicks the first (4001)", kicked === 4001, `close code ${kicked}`);

  if (typeof second !== "string") {
    // Walk from the front door to the north road (the warp to route1), then check the
    // destination was saved. The first step up is into the house wall and must not move.
    let warp: { to: string; ticket: string } | undefined;
    second.onMessage("warp", (m) => (warp = m));
    second.onMessage("wildEncounter", () => {});
    const start = second.state.players.get(second.sessionId);
    check("new trainer starts at their front door", start?.x === 27 && start?.y === 37, JSON.stringify(start));
    second.send("move", "up");
    await sleep(250);
    const blocked = second.state.players.get(second.sessionId);
    check("house wall blocks", blocked?.y === 37, JSON.stringify(blocked));
    for (const dir of VANIVILLE_TO_ROUTE1) {
      if (warp) break;
      second.send("move", dir);
      await sleep(210);
    }
    check("warp received", !!warp, "walked the whole route without a warp");
    if (warp) {
      const saved = await pool.query("SELECT t.map_id FROM trainers t JOIN accounts a ON a.id = t.account_id WHERE a.username = $1", [user]);
      check("warp destination saved before arriving", saved.rows[0]?.map_id === warp.to, JSON.stringify(saved.rows[0]));
      await second.leave();
      const other = await join(token, warp.to, { ticket: warp.ticket });
      check("ticket works for its owner", typeof other !== "string", String(other));
      if (typeof other !== "string") await other.leave();
      const reuse = await join(token, "vaniville", { ticket: warp.ticket });
      check("used ticket can't return you", typeof reuse === "string", String(reuse));
    }
  }
}

console.log("appearance");
const calem = {
  gender: "f2",
  parts: {
    face: { part: "f2_face01" }, hair: { part: "f2_hair_short" },
    hat: { part: "f2_hat_hun", color: "d01b01" }, tops: { part: "f2_tops_jersey", color: "d01b02" },
    btms: { part: "f2_btms_skinny", color: "d01b01" }, shoes: { part: "f2_shoes_sboots", color: "d01b01" },
    bag: { part: "f2_bag01", color: "d01b01" },
  },
};
r = await call("GET", "/auth/me", undefined, token);
check("no look before character creation", r.data.trainer?.appearance === null, JSON.stringify(r.data));
check("intro not seen yet", r.data.trainer?.introDone === false, JSON.stringify(r.data));
r = await call("POST", "/trainer/intro", undefined, token);
check("intro needs a look first", r.status === 400, JSON.stringify(r));
r = await call("POST", "/trainer/story", { event: "neighbors" }, token);
check("story events need the intro first", r.status === 400, JSON.stringify(r));
r = await call("PUT", "/trainer/appearance", { look: { ...calem, gender: "f9" } }, token);
check("unknown gender rejected", r.status === 400, JSON.stringify(r));
r = await call("PUT", "/trainer/appearance", { look: { ...calem, parts: { ...calem.parts, hat: { part: "f2_tops_jersey", color: "d01b01" } } } }, token);
check("part in the wrong slot rejected", r.status === 400, JSON.stringify(r));
r = await call("PUT", "/trainer/appearance", { look: { ...calem, parts: { ...calem.parts, tops: { part: "f2_tops_jersey", color: "zz99" } } } }, token);
check("made-up color rejected", r.status === 400, JSON.stringify(r));
r = await call("PUT", "/trainer/appearance", { look: { ...calem, parts: { ...calem.parts, bag: undefined } } }, token);
check("missing required slot rejected", r.status === 400, JSON.stringify(r));
r = await call("PUT", "/trainer/appearance", { look: calem }, undefined);
check("needs login", r.status === 401, JSON.stringify(r));
r = await call("PUT", "/trainer/appearance", { look: calem }, token);
check("valid look saved", r.status === 200 && r.data.trainer?.appearance?.parts?.tops?.color === "d01b02", JSON.stringify(r));
r = await call("GET", "/auth/me", undefined, token);
check("look comes back on /auth/me", r.data.trainer?.appearance?.gender === "f2", JSON.stringify(r.data));
r = await call("POST", "/trainer/intro", undefined, token);
check("intro marked as seen", r.status === 200 && r.data.trainer?.introDone === true, JSON.stringify(r));
r = await call("GET", "/auth/me", undefined, token);
check("intro flag saved", r.data.trainer?.introDone === true, JSON.stringify(r.data));
r = await call("POST", "/trainer/story", { event: "gotStarter" }, token);
check("only client cutscenes can be marked", r.status === 400, JSON.stringify(r));
r = await call("POST", "/trainer/story", { event: "neighbors" }, token);
check("neighbors scene marked as seen", r.status === 200 && r.data.trainer?.story?.includes("neighbors"), JSON.stringify(r));
const looked = await join(token, (await call("GET", "/auth/me", undefined, token)).data.trainer.mapId);
if (typeof looked !== "string") {
  await sleep(300);
  const me = looked.state.players.get(looked.sessionId);
  check("look synced to the room", JSON.parse(me?.look || "{}").parts?.hat?.part === "f2_hat_hun", JSON.stringify(me));
  await looked.leave();
} else {
  check("look synced to the room", false, looked);
}

console.log("logout");
r = await call("POST", "/auth/logout", undefined, token);
check("logout → 204", r.status === 204, JSON.stringify(r));
r = await call("GET", "/auth/me", undefined, token);
check("token dead after logout", r.status === 401, JSON.stringify(r));

console.log(failures ? `\n${failures} check(s) failed` : "\nall checks passed");
await pool.end();
process.exit(failures ? 1 : 0);

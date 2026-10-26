import { Room, ServerError, type AuthContext, type Client } from "colyseus";
import { MapState, Player } from "./state.ts";
import { pool } from "../db/pool.ts";
import { findSession, type SessionTrainer } from "../auth/sessions.ts";
import {
  type Direction, type GameMap, isWalkable, rollEncounter, step, tileAt, TRAINERS, trainerSeeing, warpAt,
} from "../world/maps.ts";
import { claimOnline, releaseOnline } from "../world/online.ts";
import { issueTicket, redeemTicket, type Transfer } from "../world/transfers.ts";
import { healParty, itemCount, loadParty, saveParty, storeCaught, useItem } from "../battle/party.ts";
import { generate, type Mon } from "../battle/pokemon.ts";
import { BALLS, WildBattle, type Action, type Update } from "../battle/wild.ts";

// One room type per map (registered in index.ts). If a map fills up, Colyseus opens
// another instance of it — effectively a channel.

const DIRECTIONS = new Set<Direction>(["up", "down", "left", "right"]);
const STEP_COOLDOWN_MS = 200; // fastest allowed walking pace; tune once the client exists

interface JoinOptions {
  ticket?: string;
}

interface AuthData {
  trainer: SessionTrainer;
  transfer?: Transfer;
}

export class MapRoom extends Room<{ state: MapState }> {
  maxClients = 100;
  private map!: GameMap;
  private lastStepAt = new Map<string, number>();
  private battles = new Map<string, WildBattle>(); // sessionId → the battle they're in
  private trainerBattles = new Map<string, string>(); // sessionId → trainer id, for trainer battles
  private starting = new Set<string>(); // a battle is being set up (loading the party)
  private warping = new Set<string>();

  onCreate(options: { map: GameMap }) {
    this.map = options.map;
    this.setState(new MapState({ mapId: this.map.id, originX: this.map.origin?.x ?? -1, originY: this.map.origin?.y ?? -1 }));

    this.onMessage("move", (client, dir: unknown) => this.handleMove(client, dir));

    this.onMessage("battle", (client, action: unknown) => this.handleBattle(client, action));
  }

  // Runs when the client asks for a seat, with its login token (client.auth.token in the SDK).
  // Static, because that is the stage every SDK sends the token in: the Godot SDK only sends it
  // here, not again when the room connection opens.
  static async onAuth(token: string, _options: unknown, _context: AuthContext): Promise<AuthData> {
    const trainer = await findSession(token);
    if (!trainer) throw new ServerError(401, "Not logged in.");
    return { trainer };
  }

  // You can only join the map your trainer is saved on, or the one a warp ticket points to.
  onJoin(client: Client, options: JoinOptions = {}, auth: AuthData) {
    const { trainer } = auth;
    const transfer = redeemTicket(options.ticket, this.map.id, trainer.trainerId);
    if (!transfer && trainer.mapId !== this.map.id) throw new ServerError(403, `Your trainer is in ${trainer.mapId}.`);
    (client.auth as AuthData).transfer = transfer;
    claimOnline(trainer.trainerId, client);
    const spawn = transfer ?? (isWalkable(this.map, trainer.x, trainer.y) ? trainer : this.map.spawn);
    this.state.players.set(client.sessionId, new Player({
      name: trainer.name,
      x: spawn.x,
      y: spawn.y,
      facing: transfer?.facing ?? trainer.facing,
      look: trainer.appearance ? JSON.stringify(trainer.appearance) : "",
    }));
    // The NPC trainers on this map, and which this player has already beaten.
    client.send("npcs", (this.map.trainers ?? []).map((t) => {
      const def = TRAINERS[t.id];
      return { id: t.id, name: def?.name, className: def?.class, model: def?.model, x: t.x, y: t.y,
        facing: t.facing, beaten: trainer.flags[`beat:${t.id}`] === true };
    }));
  }

  async onLeave(client: Client) {
    const auth = client.auth as AuthData;
    const player = this.state.players.get(client.sessionId);
    this.state.players.delete(client.sessionId);
    this.lastStepAt.delete(client.sessionId);
    // Leaving mid-battle (disconnect, closing the game) counts as running away; damage is kept.
    const battle = this.battles.get(client.sessionId);
    this.battles.delete(client.sessionId);
    this.trainerBattles.delete(client.sessionId);
    try {
      if (battle) await saveParty(auth.trainer.trainerId, battle.party);
      if (this.warping.delete(client.sessionId) || !player) return; // the warp already saved the destination
      await pool.query(
        "UPDATE trainers SET x = $2, y = $3, facing = $4 WHERE id = $1 AND map_id = $5",
        [auth.trainer.trainerId, player.x, player.y, player.facing, this.map.id],
      );
    } finally {
      // Only once everything is saved: whatever runs next for this trainer (a new login, a new game)
      // sees the final state.
      releaseOnline(auth.trainer.trainerId, client);
    }
  }

  private async handleMove(client: Client, dir: unknown) {
    const player = this.state.players.get(client.sessionId);
    if (!player || typeof dir !== "string" || !DIRECTIONS.has(dir as Direction)) return;
    if (this.inBattle(client) || this.warping.has(client.sessionId)) return;

    const now = Date.now();
    if (now - (this.lastStepAt.get(client.sessionId) ?? 0) < STEP_COOLDOWN_MS) return;

    player.facing = dir;
    const next = step(player.x, player.y, dir as Direction);
    if (this.map.heal && next.x === this.map.heal.x && next.y === this.map.heal.y) {
      // Walking into your own front door: Mom heals your Pokémon.
      this.lastStepAt.set(client.sessionId, now);
      await healParty((client.auth as AuthData).trainer.trainerId);
      client.send("healed", {});
      return;
    }
    if (!isWalkable(this.map, next.x, next.y)) return; // turned to face the wall, didn't move

    this.lastStepAt.set(client.sessionId, now);
    player.x = next.x;
    player.y = next.y;

    const warp = warpAt(this.map, next.x, next.y);
    if (warp) {
      // Save the destination first, so a disconnect mid-warp still lands the trainer there.
      const { trainerId } = (client.auth as AuthData).trainer;
      this.warping.add(client.sessionId);
      await pool.query("UPDATE trainers SET map_id = $2, x = $3, y = $4, facing = $5 WHERE id = $1",
        [trainerId, warp.to, warp.toX, warp.toY, player.facing]);
      const ticket = issueTicket({ trainerId, mapId: warp.to, x: warp.toX, y: warp.toY, facing: player.facing });
      client.send("warp", { to: warp.to, ticket });
      return;
    }

    if (tileAt(this.map, next.x, next.y) === "G") {
      const wild = rollEncounter(this.map);
      if (wild) await this.startBattle(client, wild);
      if (wild) return;
    }

    // Walked into a trainer's line of sight.
    const { trainer } = client.auth as AuthData;
    const seen = trainerSeeing(this.map, next.x, next.y, (id) => trainer.flags[`beat:${id}`] === true);
    if (seen) await this.startTrainerBattle(client, seen.spot.id, seen.distance);
  }

  private inBattle(client: Client): boolean {
    return this.battles.has(client.sessionId) || this.starting.has(client.sessionId);
  }

  // --- wild battles ------------------------------------------------------------------------------

  private async startBattle(client: Client, wild: { species: string; level: number }) {
    const { trainer } = client.auth as AuthData;
    this.starting.add(client.sessionId);
    try {
      const party = await loadParty(trainer.trainerId);
      if (!party.some((m) => m.currentHp !== 0)) return; // no Pokémon that can fight: wild ones stay away
      const battle = new WildBattle(party, [generate(wild.species, wild.level)], this.hooks(trainer));
      const update = await battle.start();
      this.battles.set(client.sessionId, battle);
      client.send("battleStart", update);
    } finally {
      this.starting.delete(client.sessionId);
    }
  }

  private hooks(trainer: SessionTrainer) {
    return {
      playerName: trainer.name,
      useBall: (item: string) => useItem(trainer.trainerId, item),
      balls: async () => Object.fromEntries(await Promise.all(
        Object.keys(BALLS).map(async (b) => [b, await itemCount(trainer.trainerId, b)]))),
    };
  }

  /** A trainer spotted the player: they walk up and battle. Their team comes from data/trainers.json. */
  private async startTrainerBattle(client: Client, id: string, distance: number) {
    const { trainer } = client.auth as AuthData;
    const def = TRAINERS[id];
    const spot = this.map.trainers?.find((t) => t.id === id);
    if (!def || !spot) return;
    this.starting.add(client.sessionId);
    try {
      const party = await loadParty(trainer.trainerId);
      if (!party.some((m) => m.currentHp !== 0)) return; // trainers don't battle someone without Pokémon
      const team: Mon[] = def.team.map((t) => {
        const m = generate(t.species, t.level);
        m.ivs = m.ivs.map(() => 0); // the team table's IV byte is 0 for these trainers
        return m;
      });
      const battle = new WildBattle(party, team, this.hooks(trainer), { name: def.name, className: def.class, money: def.money });
      this.trainerBattles.set(client.sessionId, id);
      const update = await battle.start();
      this.battles.set(client.sessionId, battle);
      // The trainer walks up to the tile in front of the player (distance - 1 steps).
      let to = { x: spot.x, y: spot.y };
      for (let i = 1; i < distance; i++) to = step(to.x, to.y, spot.facing);
      client.send("battleStart", { ...update, trainer: { id, name: def.name, className: def.class, model: def.model,
        from: { x: spot.x, y: spot.y }, to, facing: spot.facing } });
    } finally {
      this.starting.delete(client.sessionId);
    }
  }

  private async handleBattle(client: Client, raw: unknown) {
    const battle = this.battles.get(client.sessionId);
    const action = parseAction(raw);
    if (!battle || !action) return;
    let update: Update;
    try {
      update = await battle.act(action);
    } catch (err) {
      console.error("battle action failed:", err);
      return;
    }
    if (update.result) await this.endBattle(client, battle, update.result, update.prize ?? 0);
    client.send("battleUpdate", update);
  }

  private async endBattle(client: Client, battle: WildBattle, result: NonNullable<Update["result"]>, prize: number) {
    const { trainer } = client.auth as AuthData;
    this.battles.delete(client.sessionId);
    const trainerId = this.trainerBattles.get(client.sessionId);
    this.trainerBattles.delete(client.sessionId);
    if (trainerId && result === "win") {
      // Beaten once, never again; the prize goes to the player's money.
      await pool.query(
        "UPDATE trainers SET flags = flags || jsonb_build_object($2::text, true), money = money + $3 WHERE id = $1",
        [trainer.trainerId, `beat:${trainerId}`, prize]);
      trainer.flags = { ...trainer.flags, [`beat:${trainerId}`]: true };
    }
    await saveParty(trainer.trainerId, battle.party);
    if (result === "caught") await storeCaught(trainer.trainerId, battle.wild, battle.caughtBall ?? "pokeball", this.map.id);
    if (result === "lost") await this.blackOut(client);
  }

  /** Out of usable Pokémon: back home to Vaniville with the party healed (Mom takes care of them). */
  private async blackOut(client: Client) {
    const { trainer } = client.auth as AuthData;
    const player = this.state.players.get(client.sessionId);
    await healParty(trainer.trainerId);
    const home = { mapId: "vaniville", x: 27, y: 37, facing: "down" };
    if (this.map.id === home.mapId && player) {
      player.x = home.x;
      player.y = home.y;
      player.facing = home.facing;
      return;
    }
    this.warping.add(client.sessionId);
    await pool.query("UPDATE trainers SET map_id = $2, x = $3, y = $4, facing = $5 WHERE id = $1",
      [trainer.trainerId, home.mapId, home.x, home.y, home.facing]);
    const ticket = issueTicket({ trainerId: trainer.trainerId, ...home });
    // Sent after the battle's last update, so the client finishes the "blacked out" text first.
    setTimeout(() => client.send("warp", { to: home.mapId, ticket, blackout: true }), 0);
  }
}

function parseAction(raw: unknown): Action | null {
  if (!raw || typeof raw !== "object") return null;
  const a = raw as Record<string, unknown>;
  switch (a.type) {
    case "move": return Number.isInteger(a.index) && (a.index as number) >= 0 && (a.index as number) < 4 ? { type: "move", index: a.index as number } : null;
    case "switch": return Number.isInteger(a.slot) && (a.slot as number) >= 0 && (a.slot as number) < 6 ? { type: "switch", slot: a.slot as number } : null;
    case "ball": return typeof a.item === "string" && a.item in BALLS ? { type: "ball", item: a.item } : null;
    case "run": return { type: "run" };
    default: return null;
  }
}

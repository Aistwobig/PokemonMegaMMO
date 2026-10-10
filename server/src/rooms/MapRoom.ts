import { Room, ServerError, type AuthContext, type Client } from "colyseus";
import { MapState, Player } from "./state.ts";
import { pool } from "../db/pool.ts";
import { findSession, type SessionTrainer } from "../auth/sessions.ts";
import { type Direction, type GameMap, isWalkable, rollEncounter, step, tileAt, warpAt } from "../world/maps.ts";
import { claimOnline, releaseOnline } from "../world/online.ts";
import { issueTicket, redeemTicket, type Transfer } from "../world/transfers.ts";

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
  private inBattle = new Set<string>();
  private warping = new Set<string>();

  onCreate(options: { map: GameMap }) {
    this.map = options.map;
    this.setState(new MapState({ mapId: this.map.id }));

    this.onMessage("move", (client, dir: unknown) => this.handleMove(client, dir));

    // Placeholder until Phase 3: the client dismisses the encounter screen.
    this.onMessage("battleEnd", (client) => this.inBattle.delete(client.sessionId));
  }

  // Runs before onJoin. The client sends its login token (client.auth.token in the SDK).
  // You can only join the map your trainer is saved on, or the one a warp ticket points to.
  async onAuth(_client: Client, options: JoinOptions = {}, context: AuthContext): Promise<AuthData> {
    const trainer = await findSession(context.token);
    if (!trainer) throw new ServerError(401, "Not logged in.");
    const transfer = redeemTicket(options.ticket, this.map.id, trainer.trainerId);
    if (!transfer && trainer.mapId !== this.map.id) throw new ServerError(403, `Your trainer is in ${trainer.mapId}.`);
    return { trainer, transfer };
  }

  onJoin(client: Client, _options: JoinOptions, auth: AuthData) {
    const { trainer, transfer } = auth;
    claimOnline(trainer.trainerId, client);
    const spawn = transfer ?? (isWalkable(this.map, trainer.x, trainer.y) ? trainer : this.map.spawn);
    this.state.players.set(client.sessionId, new Player({
      name: trainer.name,
      x: spawn.x,
      y: spawn.y,
      facing: transfer?.facing ?? trainer.facing,
    }));
  }

  async onLeave(client: Client) {
    const auth = client.auth as AuthData;
    const player = this.state.players.get(client.sessionId);
    this.state.players.delete(client.sessionId);
    this.lastStepAt.delete(client.sessionId);
    this.inBattle.delete(client.sessionId);
    releaseOnline(auth.trainer.trainerId, client);
    if (this.warping.delete(client.sessionId) || !player) return; // the warp already saved the destination
    await pool.query(
      "UPDATE trainers SET x = $2, y = $3, facing = $4 WHERE id = $1 AND map_id = $5",
      [auth.trainer.trainerId, player.x, player.y, player.facing, this.map.id],
    );
  }

  private async handleMove(client: Client, dir: unknown) {
    const player = this.state.players.get(client.sessionId);
    if (!player || typeof dir !== "string" || !DIRECTIONS.has(dir as Direction)) return;
    if (this.inBattle.has(client.sessionId) || this.warping.has(client.sessionId)) return;

    const now = Date.now();
    if (now - (this.lastStepAt.get(client.sessionId) ?? 0) < STEP_COOLDOWN_MS) return;

    player.facing = dir;
    const next = step(player.x, player.y, dir as Direction);
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
      if (wild) {
        this.inBattle.add(client.sessionId);
        client.send("wildEncounter", wild);
      }
    }
  }
}

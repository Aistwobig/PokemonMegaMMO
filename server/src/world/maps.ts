import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

// Map data lives in server/data/maps/*.json. Spawns, warps and encounters are hand-written; real
// towns also carry their walkable tiles from the RomFS (importer/tools/make_map.py), the only map
// data the server takes from the game. Placeholder maps are hand-drawn.
// Tile legend:  . walkable   # blocked   G tall grass (walkable, can trigger encounters)

export type Direction = "up" | "down" | "left" | "right";

export interface Warp {
  x: number;
  y: number;
  to: string; // target map id
  toX: number;
  toY: number;
}

export interface Encounter {
  species: string; // Showdown species id, e.g. "fletchling"
  minLevel: number;
  maxLevel: number;
  weight: number;
}

export interface GameMap {
  id: string;
  name: string;
  origin?: { x: number; y: number }; // real maps: top-left tile in the X/Y map matrix
  tiles: string[];
  spawn: { x: number; y: number };
  warps: Warp[];
  encounterRate: number; // chance per step in grass, 0..1
  encounters: Encounter[];
}

const MAPS_DIR = join(import.meta.dirname, "../../data/maps");

export function loadMaps(): Map<string, GameMap> {
  const maps = new Map<string, GameMap>();
  for (const file of readdirSync(MAPS_DIR).filter((f) => f.endsWith(".json"))) {
    const map = JSON.parse(readFileSync(join(MAPS_DIR, file), "utf8")) as GameMap;
    maps.set(map.id, map);
  }
  for (const map of maps.values()) {
    for (const warp of map.warps) {
      if (!maps.has(warp.to)) throw new Error(`${map.id}: warp to unknown map "${warp.to}"`);
    }
  }
  return maps;
}

export function tileAt(map: GameMap, x: number, y: number): string {
  return map.tiles[y]?.[x] ?? "#"; // outside the map counts as blocked
}

export function isWalkable(map: GameMap, x: number, y: number): boolean {
  return tileAt(map, x, y) !== "#";
}

export function step(x: number, y: number, dir: Direction): { x: number; y: number } {
  switch (dir) {
    case "up": return { x, y: y - 1 };
    case "down": return { x, y: y + 1 };
    case "left": return { x: x - 1, y };
    case "right": return { x: x + 1, y };
  }
}

export function warpAt(map: GameMap, x: number, y: number): Warp | undefined {
  return map.warps.find((w) => w.x === x && w.y === y);
}

export function rollEncounter(map: GameMap, random = Math.random): { species: string; level: number } | null {
  if (map.encounters.length === 0 || random() >= map.encounterRate) return null;
  const total = map.encounters.reduce((sum, e) => sum + e.weight, 0);
  let roll = random() * total;
  for (const e of map.encounters) {
    roll -= e.weight;
    if (roll < 0) {
      const level = e.minLevel + Math.floor(random() * (e.maxLevel - e.minLevel + 1));
      return { species: e.species, level };
    }
  }
  return null;
}

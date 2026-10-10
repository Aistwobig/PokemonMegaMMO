import showdown from "pokemon-showdown";

const { BattleStream, getPlayerStreams, Teams } = showdown; // CommonJS package: no named ESM exports

// Thin wrapper around the Showdown simulator. Showdown only resolves turns; catching,
// EXP, evolution and AI live in our own code around it (see PLAN.md → Battles).

export interface PokemonSet {
  name?: string;
  species: string;
  item?: string;
  ability: string;
  moves: string[];
  nature?: string;
  level?: number;
  gender?: string;
  evs?: Partial<Record<StatId, number>>;
  ivs?: Partial<Record<StatId, number>>;
}
type StatId = "hp" | "atk" | "def" | "spa" | "spd" | "spe";

export interface BattleSide {
  name: string;
  team: PokemonSet[];
}

// Gen 6 rules with no clauses; Mega Evolution is part of Gen 6 mechanics.
export const FORMAT = "gen6customgame";

export function createBattle(p1: BattleSide, p2: BattleSide, seed?: number[]) {
  const streams = getPlayerStreams(new BattleStream());
  const spec = { formatid: FORMAT, ...(seed && { seed }) };
  const player = (side: BattleSide) =>
    JSON.stringify({ name: side.name, team: Teams.pack(side.team as Parameters<typeof Teams.pack>[0]) });
  void streams.omniscient.write(`>start ${JSON.stringify(spec)}\n>player p1 ${player(p1)}\n>player p2 ${player(p2)}`);
  return streams;
}

/** Pulls the decision request out of a chunk of a player's stream, if there is one. */
export function parseRequest(chunk: string): any | null {
  for (const line of chunk.split("\n")) {
    if (line.startsWith("|request|")) return JSON.parse(line.slice("|request|".length));
  }
  return null;
}

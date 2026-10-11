import { readFileSync } from "node:fs";
import { join } from "node:path";
import { randomInt } from "node:crypto";
import showdown from "pokemon-showdown";
import type { PokemonSet } from "./showdown.ts";

// A Pokémon as we store it, plus the game rules Showdown leaves to us: generating wild Pokémon,
// stats, EXP curves and level-up moves. Species data comes from Showdown's Gen 6 dex; catch rates,
// EXP yields and growth rates from data/species.json.

const { Dex } = showdown as any;
export const dex = Dex.mod("gen6");

export type StatId = "hp" | "atk" | "def" | "spa" | "spd" | "spe";
export const STATS: StatId[] = ["hp", "atk", "def", "spa", "spd", "spe"];

export interface Mon {
  id?: string; // database id, once saved
  species: string; // Showdown id, e.g. "froakie"
  nickname: string | null;
  level: number;
  exp: number;
  nature: string;
  ability: string;
  gender: "M" | "F" | "N";
  shiny: boolean;
  heldItem: string | null;
  ivs: number[]; // hp, atk, def, spa, spd, spe
  evs: number[];
  moves: string[]; // move ids
  currentHp: number | null; // null = full
  status: string | null;
  slot: number;
}

interface SpeciesExtra {
  catchRate: number;
  baseExp: number;
  growth: Growth;
  evs: Partial<Record<StatId, number>>;
}
type Growth = "fast" | "medium-fast" | "medium-slow" | "slow" | "erratic" | "fluctuating";

const EXTRA: Record<string, SpeciesExtra> = JSON.parse(
  readFileSync(join(import.meta.dirname, "../../data/species.json"), "utf8"),
);
const DEFAULT_EXTRA: SpeciesExtra = { catchRate: 45, baseExp: 64, growth: "medium-slow", evs: {} };

export function extra(species: string): SpeciesExtra {
  return EXTRA[species] ?? DEFAULT_EXTRA;
}

export function speciesName(species: string): string {
  return dex.species.get(species).name;
}

/** Total EXP needed to reach a level. */
export function expForLevel(growth: Growth, n: number): number {
  if (n <= 1) return 0;
  switch (growth) {
    case "fast": return Math.floor((4 * n ** 3) / 5);
    case "medium-fast": return n ** 3;
    case "medium-slow": return Math.floor((6 / 5) * n ** 3 - 15 * n ** 2 + 100 * n - 140);
    case "slow": return Math.floor((5 * n ** 3) / 4);
    case "erratic":
      if (n <= 50) return Math.floor((n ** 3 * (100 - n)) / 50);
      if (n <= 68) return Math.floor((n ** 3 * (150 - n)) / 100);
      if (n <= 98) return Math.floor((n ** 3 * Math.floor((1911 - 10 * n) / 3)) / 500);
      return Math.floor((n ** 3 * (160 - n)) / 100);
    case "fluctuating":
      if (n <= 15) return Math.floor((n ** 3 * (Math.floor((n + 1) / 3) + 24)) / 50);
      if (n <= 36) return Math.floor((n ** 3 * (n + 14)) / 50);
      return Math.floor((n ** 3 * (Math.floor(n / 2) + 32)) / 50);
  }
}

/** Gen 3+ stat formula. */
export function stat(mon: Mon, s: StatId): number {
  const sp = dex.species.get(mon.species);
  const i = STATS.indexOf(s);
  const base = sp.baseStats[s];
  const core = Math.floor(((2 * base + mon.ivs[i] + Math.floor(mon.evs[i] / 4)) * mon.level) / 100);
  if (s === "hp") return sp.name === "Shedinja" ? 1 : core + mon.level + 10;
  const nature = dex.natures.get(mon.nature);
  const mult = nature.plus === s ? 1.1 : nature.minus === s ? 0.9 : 1;
  return Math.floor((core + 5) * mult);
}

export function maxHp(mon: Mon): number {
  return stat(mon, "hp");
}

export function hp(mon: Mon): number {
  return mon.currentHp ?? maxHp(mon);
}

/** Moves learned by level-up in Gen 6 at exactly this level (in learnset order). */
export function movesLearnedAt(species: string, level: number): string[] {
  const out: string[] = [];
  for (const [move, sources] of Object.entries(learnset(species))) {
    if (sources.some((s) => s === `6L${level}`)) out.push(move);
  }
  return out;
}

/** The last four level-up moves known by this level, like the games give wild Pokémon. */
export function movesAtLevel(species: string, level: number): string[] {
  const learned: { move: string; at: number }[] = [];
  for (const [move, sources] of Object.entries(learnset(species))) {
    for (const s of sources) {
      const m = /^6L(\d+)$/.exec(s);
      if (m && Number(m[1]) <= level) learned.push({ move, at: Number(m[1]) });
    }
  }
  learned.sort((a, b) => a.at - b.at);
  const unique = [...new Set(learned.map((l) => l.move))];
  return unique.slice(-4);
}

function learnset(species: string): Record<string, string[]> {
  let sp = dex.species.get(species);
  // Formes without their own learnset use the base species'.
  const own = Dex.data.Learnsets[sp.id]?.learnset;
  if (own) return own;
  sp = dex.species.get(sp.baseSpecies);
  return Dex.data.Learnsets[sp.id]?.learnset ?? {};
}

const pick = <T>(xs: T[]): T => xs[randomInt(xs.length)];

/** A freshly generated Pokémon: random IVs, nature, ability (not hidden), gender and shininess. */
export function generate(species: string, level: number): Mon {
  const sp = dex.species.get(species);
  if (!sp.exists) throw new Error(`unknown species ${species}`);
  const abilities = [sp.abilities[0], sp.abilities[1]].filter(Boolean);
  let gender: "M" | "F" | "N";
  if (sp.gender) gender = sp.gender as "M" | "F" | "N";
  else gender = Math.random() < (sp.genderRatio?.M ?? 0.5) ? "M" : "F";
  const natures = dex.natures.all().map((n: { id: string }) => n.id);
  return {
    species: sp.id,
    nickname: null,
    level,
    exp: expForLevel(extra(sp.id).growth, level),
    nature: pick(natures),
    ability: dex.abilities.get(pick(abilities)).id,
    gender,
    shiny: randomInt(4096) === 0,
    heldItem: null,
    ivs: STATS.map(() => randomInt(32)),
    evs: STATS.map(() => 0),
    moves: movesAtLevel(sp.id, level),
    currentHp: null,
    status: null,
    slot: 0,
  };
}

/** The Showdown team entry for a stored Pokémon. */
export function toSet(mon: Mon): PokemonSet {
  const toStats = (xs: number[]) => Object.fromEntries(STATS.map((s, i) => [s, xs[i]]));
  return {
    name: mon.nickname ?? speciesName(mon.species),
    species: speciesName(mon.species),
    ability: mon.ability,
    moves: mon.moves,
    nature: mon.nature,
    level: mon.level,
    gender: mon.gender === "N" ? "" : mon.gender,
    ivs: toStats(mon.ivs),
    evs: toStats(mon.evs),
    ...(mon.heldItem && { item: mon.heldItem }),
  };
}

/** The level-up evolution this Pokémon qualifies for at its level, if any. */
export function evolutionAt(mon: Mon): string | null {
  const sp = dex.species.get(mon.species);
  for (const name of sp.evos ?? []) {
    const evo = dex.species.get(name);
    if (!evo.exists || evo.gen > 6) continue;
    if (!evo.evoType && evo.evoLevel && mon.level >= evo.evoLevel && !evo.evoCondition && !evo.evoItem) return evo.id;
  }
  return null;
}

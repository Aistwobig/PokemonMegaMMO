import type pg from "pg";
import { pool, transaction } from "../db/pool.ts";
import { dex, expForLevel, extra, generate, hp, maxHp, speciesName, stat, type Mon } from "./pokemon.ts";

// Reading and writing a trainer's Pokémon and bag.

type Db = pg.Pool | pg.PoolClient;

export const STARTERS = ["chespin", "fennekin", "froakie"];
const STARTER_LEVEL = 5;
const STARTER_BALLS = 10;

function fromRow(r: any): Mon {
  return {
    id: String(r.id), species: r.species, nickname: r.nickname, level: r.level, exp: r.exp,
    nature: r.nature, ability: r.ability, gender: r.gender, shiny: r.shiny, heldItem: r.held_item,
    ivs: r.ivs, evs: r.evs, moves: r.moves, currentHp: r.current_hp, status: r.status, slot: r.slot,
  };
}

export async function loadParty(trainerId: string, db: Db = pool): Promise<Mon[]> {
  const { rows } = await db.query(
    "SELECT * FROM pokemon WHERE owner_id = $1 AND location = 'party' ORDER BY slot", [trainerId]);
  return rows.map(fromRow);
}

/** What the client shows: the party and the bag. */
export async function partySummary(trainerId: string) {
  const party = await loadParty(trainerId);
  const { rows } = await pool.query("SELECT item, quantity FROM inventory WHERE trainer_id = $1", [trainerId]);
  const money = await pool.query("SELECT money FROM trainers WHERE id = $1", [trainerId]);
  return {
    money: money.rows[0]?.money ?? 0,
    party: party.map((m) => ({
      slot: m.slot, species: m.species, name: m.nickname ?? speciesName(m.species), level: m.level, gender: m.gender,
      shiny: m.shiny, hp: hp(m), maxHp: maxHp(m), status: m.status, moves: m.moves.map((id) => dex.moves.get(id).name),
      // PP isn't saved between battles yet: show the full PP every battle starts with (Showdown
      // gives each move 3 PP Ups, so base PP × 8/5).
      moveInfo: m.moves.map((id) => {
        const mv = dex.moves.get(id);
        return { name: mv.name, type: mv.type, category: mv.category, power: mv.basePower, accuracy: mv.accuracy, pp: Math.floor(mv.pp * 8 / 5) };
      }),
      types: dex.species.get(m.species).types,
      nature: dex.natures.get(m.nature).name, ability: dex.abilities.get(m.ability).name, exp: m.exp,
      levelExp: expForLevel(extra(m.species).growth, m.level),
      nextLevelExp: m.level < 100 ? expForLevel(extra(m.species).growth, m.level + 1) : m.exp,
      stats: { atk: stat(m, "atk"), def: stat(m, "def"), spa: stat(m, "spa"), spd: stat(m, "spd"), spe: stat(m, "spe") },
    })),
    items: Object.fromEntries(rows.map((r) => [r.item, r.quantity])),
  };
}

/** The first Pokémon, once: fails (returns null) if the trainer already has one. */
export async function giveStarter(trainerId: string, species: string): Promise<Mon | null> {
  return transaction(async (db) => {
    // Lock the trainer row so two requests can't both pass the "no Pokémon yet" check.
    await db.query("SELECT id FROM trainers WHERE id = $1 FOR UPDATE", [trainerId]);
    const { rows } = await db.query("SELECT count(*)::int AS n FROM pokemon WHERE owner_id = $1", [trainerId]);
    if (rows[0].n > 0) return null;
    const mon = generate(species, STARTER_LEVEL);
    mon.id = await insert(db, trainerId, mon, "party", null, 0, "pokeball", "aquacorde");
    await addItem(db, trainerId, "pokeball", STARTER_BALLS);
    return mon;
  });
}

/** A caught Pokémon goes to the first free party slot, or the PC when the party is full. */
export async function storeCaught(trainerId: string, mon: Mon, ball: string, mapId: string): Promise<"party" | "box"> {
  return transaction(async (db) => {
    await db.query("SELECT id FROM trainers WHERE id = $1 FOR UPDATE", [trainerId]);
    const party = await db.query("SELECT slot FROM pokemon WHERE owner_id = $1 AND location = 'party'", [trainerId]);
    const used = new Set(party.rows.map((r) => r.slot));
    for (let slot = 0; slot < 6; slot++) {
      if (!used.has(slot)) {
        await insert(db, trainerId, mon, "party", null, slot, ball, mapId);
        return "party";
      }
    }
    const boxed = await db.query(
      "SELECT box, slot FROM pokemon WHERE owner_id = $1 AND location = 'box'", [trainerId]);
    const taken = new Set(boxed.rows.map((r) => `${r.box}:${r.slot}`));
    for (let box = 0; box < 31; box++) {
      for (let slot = 0; slot < 30; slot++) {
        if (!taken.has(`${box}:${slot}`)) {
          await insert(db, trainerId, mon, "box", box, slot, ball, mapId);
          return "box";
        }
      }
    }
    throw new Error("PC is full");
  });
}

async function insert(db: Db, trainerId: string, m: Mon, location: string, box: number | null, slot: number,
  ball: string, mapId: string): Promise<string> {
  const { rows } = await db.query(
    `INSERT INTO pokemon (owner_id, original_owner_id, species, nickname, level, exp, nature, ability, gender,
       shiny, held_item, ivs, evs, moves, current_hp, status, location, box, slot, caught_ball, caught_map_id)
     VALUES ($1, $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20)
     RETURNING id`,
    [trainerId, m.species, m.nickname, m.level, m.exp, m.nature, m.ability, m.gender, m.shiny, m.heldItem,
      m.ivs, m.evs, m.moves, m.currentHp, m.status, location, box, slot, ball, mapId],
  );
  return String(rows[0].id);
}

/** Swaps two party slots (reordering; slot 0 leads in battle). False if either slot is empty. */
export async function swapParty(trainerId: string, a: number, b: number): Promise<boolean> {
  return transaction(async (db) => {
    const { rows } = await db.query(
      "SELECT id, slot FROM pokemon WHERE owner_id = $1 AND location = 'party' AND slot = ANY($2) FOR UPDATE",
      [trainerId, [a, b]]);
    if (rows.length !== 2) return false;
    const first = rows.find((r) => r.slot === a)!;
    const second = rows.find((r) => r.slot === b)!;
    // Positions are unique, so park one in a spot no real box uses while the other moves.
    await db.query("UPDATE pokemon SET location = 'box', box = -1, slot = 0 WHERE id = $1", [first.id]);
    await db.query("UPDATE pokemon SET slot = $2 WHERE id = $1", [second.id, a]);
    await db.query("UPDATE pokemon SET location = 'party', box = NULL, slot = $2 WHERE id = $1", [first.id, b]);
    return true;
  });
}

/** Saves what a battle changed: HP, status, EXP, level, EVs, moves and evolutions. */
export async function saveParty(trainerId: string, party: Mon[]): Promise<void> {
  await transaction(async (db) => {
    for (const m of party) {
      await db.query(
        `UPDATE pokemon SET species = $3, level = $4, exp = $5, evs = $6, moves = $7, current_hp = $8, status = $9
          WHERE id = $1 AND owner_id = $2`,
        [m.id, trainerId, m.species, m.level, m.exp, m.evs, m.moves, m.currentHp, m.status],
      );
    }
  });
}

/** Full HP and no status for the whole party (home, Pokémon Centers, blacking out). */
export async function healParty(trainerId: string): Promise<void> {
  await pool.query(
    "UPDATE pokemon SET current_hp = NULL, status = NULL WHERE owner_id = $1 AND location = 'party'", [trainerId]);
}

export async function itemCount(trainerId: string, item: string, db: Db = pool): Promise<number> {
  const { rows } = await db.query("SELECT quantity FROM inventory WHERE trainer_id = $1 AND item = $2", [trainerId, item]);
  return rows[0]?.quantity ?? 0;
}

export async function addItem(db: Db, trainerId: string, item: string, n: number): Promise<void> {
  await db.query(
    `INSERT INTO inventory (trainer_id, item, quantity) VALUES ($1, $2, $3)
     ON CONFLICT (trainer_id, item) DO UPDATE SET quantity = inventory.quantity + EXCLUDED.quantity`,
    [trainerId, item, n],
  );
}

/** Uses one of an item; false if the trainer has none. */
export async function useItem(trainerId: string, item: string): Promise<boolean> {
  // Quantities are always > 0 (a CHECK), so the last one deletes the row instead of reaching 0.
  const last = await pool.query(
    "DELETE FROM inventory WHERE trainer_id = $1 AND item = $2 AND quantity = 1 RETURNING item", [trainerId, item]);
  if (last.rowCount) return true;
  const more = await pool.query(
    "UPDATE inventory SET quantity = quantity - 1 WHERE trainer_id = $1 AND item = $2 AND quantity > 1 RETURNING item",
    [trainerId, item]);
  return (more.rowCount ?? 0) > 0;
}

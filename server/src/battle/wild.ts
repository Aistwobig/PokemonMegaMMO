import { randomInt } from "node:crypto";
import showdown from "pokemon-showdown";
import { FORMAT } from "./showdown.ts";
import {
  dex, evolutionAt, expForLevel, extra, maxHp, movesLearnedAt, speciesName, STATS, toSet, type Mon,
} from "./pokemon.ts";

// One battle against a wild Pokémon or an NPC trainer. Showdown resolves the turns; this adds what
// it doesn't do — the opponent's choices, Poké Balls, running away, EXP, prize money, level-ups, new
// moves and evolution — and turns Showdown's log into the messages and HP changes the client plays
// back. (Below, "wild" means the opposing side, a trainer's Pokémon included.)

const { Battle, Teams } = showdown as any;

export type Action =
  | { type: "move"; index: number }
  | { type: "switch"; slot: number }
  | { type: "ball"; item: string }
  | { type: "run" };

export interface BattleEvent {
  text?: string;
  side?: "player" | "wild";
  hp?: number;
  maxHp?: number;
  anim?: "appear" | "send" | "attack" | "hit" | "faint" | "throw" | "shake" | "caught" | "breakout" | "levelup" | "evolve";
  species?: string; // with "send"/"evolve": who is now out
}

export interface Update {
  events: BattleEvent[];
  view: BattleView;
  request: RequestView | null; // what the player must choose next; null when the battle is over
  result?: "win" | "caught" | "ran" | "lost";
  prize?: number; // money won from a trainer
}

interface MonView { slot: number; name: string; species: string; level: number; hp: number; maxHp: number; status: string | null; gender: string; shiny: boolean }
export interface BattleView {
  player: MonView | null;
  wild: MonView;
  party: MonView[];
  balls: Record<string, number>;
  trainer: { name: string; className: string; left: number } | null; // left = Pokémon still able to fight
}
export interface RequestView {
  kind: "move" | "switch";
  moves: { index: number; id: string; name: string; type: string; pp: number; maxPp: number; disabled: boolean }[];
}

export const BALLS: Record<string, number> = { pokeball: 1, greatball: 1.5, ultraball: 2 };

/** An NPC trainer: their team fights one by one; no catching, no running. */
export interface TrainerInfo {
  name: string;
  className: string;
  money: number; // prize = money × 4 × the last Pokémon's level
}

export interface WildBattleHooks {
  playerName: string;
  /** Spends one ball; false if the trainer has none left. */
  useBall(item: string): Promise<boolean>;
  balls(): Promise<Record<string, number>>;
}

export class WildBattle {
  private battle: any;
  private logPos = 0;
  private mons = new Map<any, Mon>(); // Showdown Pokémon → our stored Pokémon
  private participants = new Set<Mon>(); // fought the current opposing Pokémon (they share its EXP)
  private foes = new Map<any, Mon>(); // Showdown's opposing Pokémon → ours
  private expGiven = new Set<Mon>(); // opposing Pokémon already paid out
  private runAttempts = 0;
  private wildAppeared = false;
  private done = false;

  readonly wild: Mon; // the first opposing Pokémon (for wild battles, the one you can catch)

  constructor(readonly party: Mon[], readonly foeTeam: Mon[], private hooks: WildBattleHooks,
    readonly trainer: TrainerInfo | null = null) {
    this.wild = foeTeam[0];
  }

  private get trainerTitle(): string {
    return this.trainer ? `${this.trainer.className} ${this.trainer.name}` : "";
  }

  /** Starts the battle with the first Pokémon that can fight. */
  async start(): Promise<Update> {
    const b = new Battle({ formatid: FORMAT });
    this.battle = b;
    b.setPlayer("p1", { name: this.hooks.playerName, team: Teams.pack(this.party.map(toSet)) });
    b.setPlayer("p2", { name: this.trainer ? this.trainerTitle : "Wild", team: Teams.pack(this.foeTeam.map(toSet)) });
    this.foeTeam.forEach((m, i) => this.foes.set(b.p2.pokemon[i], m));
    // Showdown starts everyone at full health; carry over HP and status from earlier battles.
    this.party.forEach((m, i) => {
      const p = b.p1.pokemon[i];
      this.mons.set(p, m);
      this.applyStored(p, m);
    });
    const lead = this.party.findIndex((m) => m.currentHp !== 0);
    const order = [lead, ...this.party.map((_, i) => i).filter((i) => i !== lead)].map((i) => i + 1).join("");
    b.choose("p1", `team ${order}`);
    b.choose("p2", `team ${this.foeTeam.map((_, i) => i + 1).join("")}`);
    this.noteActive();
    // "A wild Bunnelby appeared!" (or the trainer's challenge) comes before "Go! Froakie!", as in the games.
    const events = await this.events();
    events.sort((x, y) => Number(y.side === "wild") - Number(x.side === "wild"));
    if (this.trainer) events.unshift({ text: `You are challenged by ${this.trainerTitle}!` });
    return this.update(events);
  }

  async act(action: Action): Promise<Update> {
    if (this.done) throw new Error("battle is over");
    const b = this.battle;
    const pre: BattleEvent[] = [];
    const req = b.p1.activeRequest;
    if (req?.forceSwitch) {
      if (action.type !== "switch") return this.update([{ text: "Choose a Pokémon to send out!" }]);
      return this.doSwitch(action.slot, true);
    }
    switch (action.type) {
      case "move": {
        const moves = req?.active?.[0]?.moves ?? [];
        const m = moves[action.index];
        if (!m || m.disabled) return this.update([]);
        b.choose("p1", `move ${action.index + 1}`);
        break;
      }
      case "switch":
        return this.doSwitch(action.slot, false);
      case "ball": {
        if (!(action.item in BALLS)) return this.update([]);
        if (this.trainer) return this.update([{ text: "The Trainer blocked your Poké Ball!" }, { text: "Don't be a thief!" }]);
        if (!(await this.hooks.useBall(action.item))) return this.update([{ text: "You don't have any of those!" }]);
        const caught = this.throwBall(action.item, pre);
        if (caught) return this.finishCaught(pre, action.item);
        this.skipPlayerTurn();
        break;
      }
      case "run": {
        if (this.trainer) return this.update([{ text: "No! There's no running from a Trainer battle!" }]);
        if (this.tryRun()) {
          this.done = true;
          return this.update([{ text: "Got away safely!" }], "ran");
        }
        pre.push({ text: "You can't escape!" });
        this.skipPlayerTurn();
        break;
      }
    }
    this.wildChooses();
    return this.afterTurn(pre);
  }

  private async doSwitch(slot: number, forced: boolean): Promise<Update> {
    const b = this.battle;
    const target = [...this.mons.entries()].find(([, m]) => m.slot === slot)?.[0];
    const pos = b.p1.pokemon.indexOf(target);
    if (!target || pos < 0 || target.fainted || target.isActive) return this.update([{ text: "That Pokémon can't battle!" }]);
    b.choose("p1", `switch ${pos + 1}`);
    if (!forced) this.wildChooses();
    return this.afterTurn([]);
  }

  private async afterTurn(pre: BattleEvent[]): Promise<Update> {
    const b = this.battle;
    const events = [...pre, ...(await this.events())];
    this.noteActive();
    // Each opposing Pokémon pays out EXP when it faints (a trainer's too, before the next comes out).
    for (const [p, m] of this.foes) {
      if (p.fainted && !this.expGiven.has(m)) {
        this.expGiven.add(m);
        this.writeBack();
        events.push(...this.gainExp(m));
        this.participants.clear();
      }
    }
    if (b.p2.pokemon.every((p: any) => p.fainted)) return this.finishWon(events);
    if (b.p2.activeRequest?.forceSwitch) {
      // The trainer sends out their next Pokémon.
      const next = b.p2.pokemon.findIndex((p: any) => !p.fainted && !p.isActive);
      b.choose("p2", `switch ${next + 1}`);
      events.push(...(await this.events()));
      this.noteActive();
    }
    if (b.p1.pokemon.every((p: any) => p.fainted)) {
      this.done = true;
      this.writeBack();
      events.push({ text: `${this.hooks.playerName} is out of usable Pokémon!` }, { text: `${this.hooks.playerName} blacked out!` });
      return this.update(events, "lost");
    }
    return this.update(events);
  }

  // --- catching and running ------------------------------------------------------------------------

  /** Gen 6 capture: the catch value from HP, catch rate, ball and status, then four shake checks. */
  private throwBall(item: string, events: BattleEvent[]): boolean {
    const w = this.battle.p2.pokemon[0];
    events.push({ text: `${this.hooks.playerName} threw a ${item === "pokeball" ? "Poké Ball" : dex.items.get(item).name}!`, anim: "throw" });
    const statusBonus = w.status === "slp" || w.status === "frz" ? 2.5 : w.status ? 1.5 : 1;
    const a = Math.floor(((3 * w.maxhp - 2 * w.hp) * extra(this.wild.species).catchRate * BALLS[item]) / (3 * w.maxhp) * statusBonus);
    let shakes = 0;
    if (a >= 255) shakes = 4;
    else {
      const b = Math.floor(65536 / (255 / Math.max(a, 1)) ** 0.1875);
      while (shakes < 4 && randomInt(65536) < b) shakes++;
    }
    for (let i = 0; i < Math.min(shakes, 3); i++) events.push({ anim: "shake" });
    if (shakes === 4) return true;
    events.push({ anim: "breakout", text: ["Oh no! The Pokémon broke free!", "Aww! It appeared to be caught!", "Aargh! Almost had it!", "Gah! It was so close, too!"][shakes] });
    return false;
  }

  /** Gen 6 escape: always if at least as fast, otherwise odds that grow with each try. */
  private tryRun(): boolean {
    const mine = this.battle.p1.active[0].getStat("spe");
    const theirs = this.battle.p2.active[0].getStat("spe");
    this.runAttempts++;
    if (mine >= theirs) return true;
    const odds = Math.floor((mine * 128) / theirs) + 30 * this.runAttempts;
    return randomInt(256) < odds;
  }

  /** The player spent the turn throwing or running: their Pokémon does nothing, the wild one acts. */
  private skipPlayerTurn(): void {
    this.battle.p1.active[0].addVolatile("mustrecharge");
    this.battle.choose("p1", "move 1");
  }

  private wildChooses(): void {
    const req = this.battle.p2.activeRequest;
    if (!req || req.wait || !req.active) return;
    const usable = req.active[0].moves.map((m: any, i: number) => ({ m, i })).filter(({ m }: any) => !m.disabled);
    const pick = usable.length ? usable[randomInt(usable.length)].i + 1 : 1;
    this.battle.choose("p2", `move ${pick}`);
  }

  // --- the end of the battle -----------------------------------------------------------------------

  private async finishWon(events: BattleEvent[]): Promise<Update> {
    this.done = true;
    this.writeBack();
    let prize = 0;
    if (this.trainer) {
      const last = this.foeTeam[this.foeTeam.length - 1];
      prize = this.trainer.money * 4 * last.level;
      events.push({ text: `You defeated ${this.trainerTitle}!` }, { text: `You got ₽${prize} for winning!` });
    }
    events.push(...this.evolve());
    const u = await this.update(events, "win");
    return prize ? { ...u, prize } : u;
  }

  private async finishCaught(events: BattleEvent[], ball: string): Promise<Update> {
    this.done = true;
    const w = this.battle.p2.pokemon[0];
    this.wild.currentHp = w.hp === w.maxhp ? null : w.hp;
    this.wild.status = w.status || null;
    this.caughtBall = ball;
    events.push({ anim: "caught", text: `Gotcha! ${speciesName(this.wild.species)} was caught!` });
    this.writeBack();
    events.push(...this.gainExp(this.wild)); // since Gen 6, catching gives EXP too
    events.push(...this.evolve());
    return this.update(events, "caught");
  }

  caughtBall: string | null = null;

  /** Copies HP and status from Showdown back onto the stored Pokémon. */
  private writeBack(): void {
    for (const [p, m] of this.mons) {
      m.currentHp = p.fainted ? 0 : p.hp >= maxHp(m) ? null : p.hp;
      m.status = p.fainted ? null : p.status || null;
    }
  }

  /** Gen 6 (X/Y) EXP: base yield × the defeated Pokémon's level / 7 (× 1.5 from a trainer), split
   *  between the Pokémon that fought it. */
  private gainExp(foe: Mon): BattleEvent[] {
    const events: BattleEvent[] = [];
    const fighters = [...this.participants].filter((m) => m.currentHp !== 0);
    if (!fighters.length) return events;
    const yieldInfo = extra(foe.species);
    const base = Math.floor((yieldInfo.baseExp * foe.level) / 7 * (this.trainer ? 1.5 : 1));
    const each = Math.max(1, Math.floor(base / fighters.length));
    for (const m of fighters) {
      const name = m.nickname ?? speciesName(m.species);
      events.push({ text: `${name} gained ${each} Exp. Points!` });
      m.exp += each;
      STATS.forEach((s, i) => {
        const gain = yieldInfo.evs[s] ?? 0;
        const total = m.evs.reduce((a, b) => a + b, 0);
        m.evs[i] = Math.min(252, m.evs[i] + Math.min(gain, 510 - total));
      });
      const growth = extra(m.species).growth;
      while (m.level < 100 && m.exp >= expForLevel(growth, m.level + 1)) {
        const before = maxHp(m);
        m.level++;
        if (m.currentHp !== null) m.currentHp += maxHp(m) - before; // a level-up adds the HP gain
        const isActive = this.battle.p1.active[0] && this.mons.get(this.battle.p1.active[0]) === m;
        events.push({ text: `${name} grew to Lv. ${m.level}!`, anim: "levelup",
          ...(isActive && { side: "player" as const, hp: m.currentHp ?? maxHp(m), maxHp: maxHp(m) }) });
        for (const move of movesLearnedAt(m.species, m.level)) {
          if (m.moves.includes(move)) continue;
          const moveName = dex.moves.get(move).name;
          if (m.moves.length < 4) {
            m.moves.push(move);
            events.push({ text: `${name} learned ${moveName}!` });
          } else {
            events.push({ text: `${name} wants to learn ${moveName}, but it already knows four moves.` });
          }
        }
      }
    }
    return events;
  }

  /** Level-up evolutions happen when the battle ends. */
  private evolve(): BattleEvent[] {
    const events: BattleEvent[] = [];
    for (const m of this.party) {
      if (m.currentHp === 0) continue;
      const into = evolutionAt(m);
      if (!into) continue;
      const before = maxHp(m);
      const oldName = m.nickname ?? speciesName(m.species);
      m.species = into;
      if (m.currentHp !== null) m.currentHp = Math.max(1, m.currentHp + maxHp(m) - before);
      events.push({ text: `What? ${oldName} is evolving!` },
        { text: `Congratulations! Your ${oldName} evolved into ${speciesName(into)}!`, anim: "evolve", species: into });
    }
    return events;
  }

  // --- turning Showdown's log into events ----------------------------------------------------------

  private async events(): Promise<BattleEvent[]> {
    const log: string[] = this.battle.log;
    const out: BattleEvent[] = [];
    for (let i = this.logPos; i < log.length; i++) {
      let line = log[i];
      if (line.startsWith("|split|")) {
        // "|split|p1" is followed by the exact (private) line, then the public one: use the first.
        if (log[i + 1]) this.describe(log[i + 1], out);
        i += 2;
        continue;
      }
      this.describe(line, out);
    }
    this.logPos = log.length;
    return out;
  }

  private describe(line: string, out: BattleEvent[]): void {
    const parts = line.split("|").slice(1);
    const [tag, a, b, c] = parts;
    const from = parts.find((p) => p.startsWith("[from]"))?.slice(7).trim();
    const side = (who: string) => (who?.startsWith("p1") ? "player" : "wild") as "player" | "wild";
    const nameOf = (who: string, start = false) => {
      const n = who?.split(": ")[1] ?? "?";
      if (side(who) !== "wild") return n;
      return this.trainer ? `${start ? "The" : "the"} opposing ${n}` : `${start ? "The" : "the"} wild ${n}`;
    };
    const hpOf = (cond: string) => {
      const [hpPart] = (cond ?? "").split(" ");
      const [cur, max] = hpPart.split("/").map(Number);
      return { hp: cur || 0, maxHp: max || undefined };
    };
    switch (tag) {
      case "switch": {
        const { hp, maxHp: mhp } = hpOf(c);
        const species = dex.species.get(b.split(",")[0]).id;
        if (side(a) === "wild" && this.trainer) {
          out.push({ text: `${this.trainerTitle} sent out ${a.split(": ")[1]}!`, side: "wild", hp, maxHp: mhp, anim: "appear", species });
        } else if (side(a) === "wild") {
          if (!this.wildAppeared) out.push({ text: `A wild ${a.split(": ")[1]} appeared!`, side: "wild", hp, maxHp: mhp, anim: "appear", species });
          this.wildAppeared = true;
        } else {
          out.push({ text: `Go! ${a.split(": ")[1]}!`, side: "player", hp, maxHp: mhp, anim: "send", species });
        }
        break;
      }
      case "move":
        out.push({ text: `${nameOf(a, true)} used ${b}!`, side: side(a), anim: "attack" });
        break;
      case "-damage":
      case "-heal": {
        const { hp, maxHp: mhp } = hpOf(b);
        const ev: BattleEvent = { side: side(a), hp, maxHp: mhp, ...(tag === "-damage" && { anim: "hit" as const }) };
        if (from === "psn" || from === "tox") ev.text = `${nameOf(a, true)} is hurt by poison!`;
        else if (from === "brn") ev.text = `${nameOf(a, true)} is hurt by its burn!`;
        else if (from === "Recoil" || from === "recoil") ev.text = `${nameOf(a, true)} is damaged by the recoil!`;
        out.push(ev);
        break;
      }
      case "-supereffective": out.push({ text: "It's super effective!" }); break;
      case "-resisted": out.push({ text: "It's not very effective..." }); break;
      case "-immune": out.push({ text: `It doesn't affect ${nameOf(a)}...` }); break;
      case "-crit": out.push({ text: "A critical hit!" }); break;
      case "-miss": out.push({ text: `${nameOf(a, true)}'s attack missed!` }); break;
      case "-fail": out.push({ text: "But it failed!" }); break;
      case "-boost":
      case "-unboost": {
        const stat = ({ atk: "Attack", def: "Defense", spa: "Sp. Atk", spd: "Sp. Def", spe: "Speed", accuracy: "accuracy", evasion: "evasiveness" } as Record<string, string>)[b] ?? b;
        const n = Number(c);
        const how = tag === "-boost" ? (n >= 2 ? "rose sharply" : "rose") : n >= 2 ? "harshly fell" : "fell";
        out.push({ text: n === 0 ? `${nameOf(a, true)}'s ${stat} won't go any ${tag === "-boost" ? "higher" : "lower"}!` : `${nameOf(a, true)}'s ${stat} ${how}!` });
        break;
      }
      case "-status": {
        const what = ({ par: "is paralyzed! It may be unable to move!", psn: "was poisoned!", tox: "was badly poisoned!", brn: "was burned!", slp: "fell asleep!", frz: "was frozen solid!" } as Record<string, string>)[b];
        if (what) out.push({ text: `${nameOf(a, true)} ${what}` });
        break;
      }
      case "-curestatus": out.push({ text: `${nameOf(a, true)} is no longer ${({ par: "paralyzed", psn: "poisoned", tox: "poisoned", brn: "burned", slp: "asleep", frz: "frozen" } as Record<string, string>)[b] ?? "affected"}!` }); break;
      case "cant": {
        if (b === "recharge") break; // our "spent the turn throwing a ball / running" trick
        const why = ({ par: "is paralyzed! It can't move!", slp: "is fast asleep.", frz: "is frozen solid!", flinch: "flinched and couldn't move!" } as Record<string, string>)[b];
        if (why) out.push({ text: `${nameOf(a, true)} ${why}` });
        break;
      }
      case "faint":
        out.push({ text: `${nameOf(a, true)} fainted!`, side: side(a), anim: "faint" });
        break;
    }
  }

  // --- state for the client ------------------------------------------------------------------------

  private noteActive(): void {
    const p = this.battle.p1.active[0];
    if (p && !p.fainted) this.participants.add(this.mons.get(p)!);
  }

  /** Wild battles: whether this is over because the wild Pokémon fainted (for the room). */
  get beaten(): boolean {
    return this.battle?.p2.pokemon.every((p: any) => p.fainted) ?? false;
  }

  private applyStored(p: any, m: Mon): void {
    if (m.currentHp === 0) {
      p.hp = 0;
      p.fainted = true;
      p.faintQueued = false;
    } else if (m.currentHp !== null) {
      p.hp = Math.min(m.currentHp, p.maxhp);
    }
    if (m.status && !p.fainted) p.setStatus(m.status, null, null, true);
  }

  private async update(events: BattleEvent[], result?: Update["result"]): Promise<Update> {
    const b = this.battle;
    const view = (p: any, m: Mon): MonView => ({
      slot: m.slot, name: m.nickname ?? speciesName(m.species), species: m.species, level: m.level,
      hp: p.fainted ? 0 : p.hp, maxHp: p.maxhp, status: p.status || null, gender: m.gender, shiny: m.shiny,
    });
    const active = b.p1.active[0];
    const party = this.party.map((m) => {
      const p = [...this.mons.entries()].find(([, mm]) => mm === m)![0];
      return { ...view(p, m), level: m.level, species: m.species, name: m.nickname ?? speciesName(m.species) };
    });
    let request: RequestView | null = null;
    const req = b.p1.activeRequest;
    if (!this.done && req && !req.wait) {
      if (req.forceSwitch) request = { kind: "switch", moves: [] };
      else if (req.active) {
        request = {
          kind: "move",
          moves: req.active[0].moves.map((m: any, index: number) => ({
            index, id: m.id, name: m.move, type: dex.moves.get(m.id).type, pp: m.pp, maxPp: m.maxpp, disabled: !!m.disabled,
          })),
        };
      }
    }
    return {
      events,
      view: {
        player: active && !this.done ? view(active, this.mons.get(active)!) : active ? view(active, this.mons.get(active)!) : null,
        wild: view(b.p2.active[0] ?? b.p2.pokemon[0], this.foes.get(b.p2.active[0] ?? b.p2.pokemon[0]) ?? this.wild),
        party,
        balls: await this.hooks.balls(),
        trainer: this.trainer
          ? { name: this.trainer.name, className: this.trainer.className, left: b.p2.pokemon.filter((p: any) => !p.fainted).length }
          : null,
      },
      request,
      ...(result && { result }),
    };
  }
}

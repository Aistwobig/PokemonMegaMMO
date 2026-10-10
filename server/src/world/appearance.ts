import { readFileSync } from "node:fs";
import { join } from "node:path";

// Character looks. A look picks a part (and color) per slot from data/appearance.json, which the
// importer generates from the trainer manifests — names only, no game assets.
//
//   { gender: "f2", parts: { face: { part: "f2_face01" }, tops: { part: "f2_tops_jersey", color: "d01b02" }, ... } }

export interface PartChoice {
  part: string;
  color?: string;
}

export interface Look {
  gender: string;
  parts: Record<string, PartChoice>;
  hairColor: number;
  skinTone: number;
}

/** How many hair colors / skin tones the client offers (TrainerModel.HAIR_COLORS, SKIN_TONES). */
export const HAIR_COLORS = 6;
export const SKIN_TONES = 4;

interface Catalog {
  [gender: string]: { label: string; parts: Record<string, { category: string; colors: string[] }> };
}

/** Slots a player picks. Bangle (the Holo Caster) is always worn; boys' legs follow their shoes;
 *  girls' legs are the "socks" slot (bare legs when it's left out). */
const REQUIRED = ["face", "hair", "shoes", "bag"];
const OPTIONAL = ["hat", "point", "tops", "btms", "body", "socks"];

const catalog: Catalog = JSON.parse(readFileSync(join(import.meta.dirname, "../../data/appearance.json"), "utf8"));

export class LookError extends Error {}

/** Returns a clean copy of the look, or throws LookError explaining what's wrong. */
export function validateLook(input: unknown): Look {
  const look = input as Look;
  if (!look || typeof look !== "object" || typeof look.gender !== "string" || !catalog[look.gender]) {
    throw new LookError("Pick girl or boy.");
  }
  if (!look.parts || typeof look.parts !== "object") throw new LookError("Missing parts.");
  const available = catalog[look.gender].parts;
  const parts: Record<string, PartChoice> = {};

  for (const [slot, choice] of Object.entries(look.parts)) {
    if (choice == null) continue;
    if (!REQUIRED.includes(slot) && !OPTIONAL.includes(slot)) throw new LookError(`Unknown slot "${slot}".`);
    if (typeof choice !== "object" || typeof choice.part !== "string") throw new LookError(`Bad choice for ${slot}.`);
    const entry = available[choice.part];
    if (!entry || entry.category !== slot) throw new LookError(`"${choice.part}" isn't a ${slot}.`);
    const color = choice.color ?? "";
    if (entry.colors.length > 0 ? !entry.colors.includes(color) : color !== "") {
      throw new LookError(`"${color}" isn't a color of ${choice.part}.`);
    }
    parts[slot] = entry.colors.length > 0 ? { part: choice.part, color } : { part: choice.part };
  }

  for (const slot of REQUIRED) if (!parts[slot]) throw new LookError(`Pick a ${slot}.`);
  if (parts.body) {
    if (parts.tops || parts.btms) throw new LookError("A one-piece replaces top and bottoms.");
  } else if (!parts.tops || !parts.btms) {
    throw new LookError("Pick a top and bottoms.");
  }
  if (parts.point && !parts.hat) throw new LookError("Accessories go on a hat.");
  const hairColor = look.hairColor ?? 0;
  if (!Number.isInteger(hairColor) || hairColor < 0 || hairColor >= HAIR_COLORS) throw new LookError("Pick a hair color.");
  const skinTone = look.skinTone ?? 0;
  if (!Number.isInteger(skinTone) || skinTone < 0 || skinTone >= SKIN_TONES) throw new LookError("Pick a skin tone.");
  return { gender: look.gender, parts, hairColor, skinTone };
}

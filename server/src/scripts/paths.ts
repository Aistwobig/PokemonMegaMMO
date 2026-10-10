// Walking directions used by the test scripts, on the real overworld maps.

const go = (dir: string, n: number): string[] => Array(n).fill(dir);

/** Vaniville: from the player's front door, around the houses to the north road (→ Route 1). */
export const VANIVILLE_TO_ROUTE1 = [...go("down", 11), ...go("left", 7), ...go("up", 48)];

/** Route 1: from where Vaniville's road arrives, straight north into Aquacorde. */
export const ROUTE1_TO_AQUACORDE = go("up", 43);

/** Aquacorde: from the south entrance, around the fountain and over the bridge (→ Route 2). */
export const AQUACORDE_TO_ROUTE2 = [...go("up", 21), ...go("left", 6), ...go("up", 9), ...go("right", 6), ...go("up", 42)];

/** Route 2: north to the big patch of tall grass, then back and forth in it. */
export const ROUTE2_GRASS = [...go("up", 15), ...Array.from({ length: 15 }, () => [...go("left", 3), ...go("right", 3)]).flat()];

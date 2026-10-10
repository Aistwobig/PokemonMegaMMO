// Runs one Gen 6 battle with no client: our Lucario Mega Evolves against a wild Fletchling.
// Proves the Showdown sim is wired up. Usage: npm run battle:demo

import { createBattle, parseRequest } from "../battle/showdown.ts";

const streams = createBattle(
  { name: "Player", team: [{ species: "Lucario", item: "Lucarionite", ability: "Justified", moves: ["Aura Sphere", "Flash Cannon"], level: 50 }] },
  { name: "Wild", team: [{ species: "Fletchling", ability: "Big Pecks", moves: ["Tackle", "Growl"], level: 3 }] },
);

async function autoPlay(stream: AsyncIterable<string> & { write(s: string): unknown }, useMega: boolean) {
  for await (const chunk of stream) {
    const request = parseRequest(chunk);
    if (!request || request.wait) continue;
    if (request.teamPreview) {
      stream.write("team 1");
    } else if (request.active) {
      const canMega = useMega && request.active[0].canMegaEvo;
      stream.write(canMega ? "move 1 mega" : "move 1");
    }
  }
}

void autoPlay(streams.p1, true);
void autoPlay(streams.p2, false);

const SHOWN = ["|move|", "|-damage|", "|-mega|", "|detailschange|", "|faint|", "|win|", "|turn|"];
for await (const chunk of streams.omniscient) {
  for (const line of chunk.split("\n")) {
    if (SHOWN.some((tag) => line.startsWith(tag))) console.log(line);
  }
  if (chunk.includes("|win|")) break;
}
process.exit(0);

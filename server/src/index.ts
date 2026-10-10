import { defineRoom, defineServer, listen, type RegisteredHandler } from "colyseus";
import { authRoutes } from "./auth/routes.ts";
import { config } from "./config.ts";
import { MapRoom } from "./rooms/MapRoom.ts";
import { loadMaps } from "./world/maps.ts";

const maps = loadMaps();

// Each map is its own room name, so the client joins e.g. "vaniville" or "route1".
const rooms: Record<string, RegisteredHandler> = {};
for (const map of maps.values()) {
  rooms[map.id] = defineRoom(MapRoom, { map });
}

const server = defineServer({
  rooms,
  // We have our own accounts (src/auth). Colyseus's built-in auth module would otherwise discard
  // tokens it can't verify as JWTs, and rooms would never see them.
  auth: false,
  express: (app) => authRoutes(app, maps),
});
await listen(server, config.port);
console.log(`Maps loaded: ${[...maps.keys()].join(", ")}`);

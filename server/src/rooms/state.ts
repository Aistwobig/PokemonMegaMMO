import { schema, t, type SchemaType } from "@colyseus/schema";

// Synced to every client in the room. Keep it to what other players need to see.

export const Player = schema({
  name: t.string(),
  x: t.int32(),
  y: t.int32(),
  facing: t.string().default("down"),
  look: t.string().default(""), // appearance as JSON ("" = not created yet); see world/appearance.ts
}, "Player");
export type Player = SchemaType<typeof Player>;

export const MapState = schema({
  mapId: t.string(),
  players: t.map(Player),
}, "MapState");
export type MapState = SchemaType<typeof MapState>;

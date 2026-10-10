# Pokemon Mega MMO — Plan

An MMO set in the Kalos region (Pokémon X) with Mega Evolution, modeled on how PokeMMO works:
the game ships **no Nintendo assets**. Each player supplies their own Pokémon X data, and the
client loads graphics, maps and audio from it.

## Ground rules

- Never distribute ROMs, decryption keys, or extracted assets.
- Players provide a decrypted RomFS dumped from **their own** 3DS (GodMode9).
- The server is authoritative: clients render and send input, the server decides outcomes.
- All randomness (encounters, IVs, damage rolls, catch checks) happens on the server.
- Non-commercial, friends-only for as long as possible. Bring-your-own-ROM lowers legal risk; it doesn't remove it.

## Architecture

| Part | Tech | Job |
|---|---|---|
| `importer/` | C# | Reads the player's RomFS, unpacks GARC archives, converts models/textures/maps/audio into a local asset cache (glTF, PNG, OGG) |
| `client/` | Godot 4 | Renders the 3D world from the asset cache, UI, input |
| `server/` | Node.js + TypeScript, Colyseus, Pokémon Showdown sim | Rooms per map, movement sync, chat, battles (Gen 6 + Mega Evolution) |
| `server/data/` | JSON/YAML, hand-written | Game logic data the server needs (see below) |
| Database | PostgreSQL | Accounts, Pokémon, PC boxes, items, badges, friends, trades |
| Cache | Redis | Sessions, online players, chat, queues |

Reference tools to study for the importer: pk3DS (game data), SPICA / Ohana3DS (models), vgmstream (audio).
They are C#, so their parsers can be reused — check each license first (GPL code changes this repo's license).

### Assets vs. game data

The player's RomFS only feeds the **client** (presentation). The server never sees a ROM, so it
owns its own game data:

| Data | Source |
|---|---|
| Models, textures, maps, music, SFX | Player's RomFS → importer → client asset cache |
| Dialogue text | Player's RomFS. Server sends message IDs (`{file, line}`), client looks up the text |
| Species, moves, abilities, items, learnsets, Megas | Showdown's Gen 6 data |
| Encounter tables, trainer teams, NPC placement, warps | `server/data/maps/<map>.yaml`, hand-written |
| Story events | Our own simple event format (talk → give item → set flag → walk), not X/Y's script bytecode |
| Collision / walkable tiles | Extracted once per map, checked into `server/data` as a tile grid |

### Movement

Grid-based, like PokeMMO. The server validates each step (tile walkable, not moving faster
than allowed). No free analog movement.

### Battles

Showdown runs turn resolution only. The server wraps it with what Showdown doesn't do:

- Wild Pokémon generation (IVs, nature, ability, shininess)
- Catching (ball formula, shake checks, party/PC placement)
- AI for wild Pokémon and NPC trainers
- After battle: EXP, EVs, level-ups, move learning, evolution, money

### Single-screen UI

One window, no second screen — like PokeMMO did for Gen 4/5. Everything from the 3DS bottom
screen is redesigned as PC UI (mouse + keyboard). We draw our own UI instead of extracting the
3DS touch-screen textures.

| X/Y bottom screen | Single-screen version |
|---|---|
| Battle: Fight / Bag / Pokémon / Run, moves, Mega button | Battle panel overlaid on the bottom of the battle scene |
| Overworld menu (Pokémon, Bag, Save…) | Pause menu (Esc) + hotkeys (e.g. B = bag, P = party) |
| PSS (online players, trades, battles) | MMO social UI: friends list, chat box, right-click a player to trade/battle |
| Map | Fullscreen town map (M) |
| Pokémon-Amie, Super Training | Out of scope for now |

**Widescreen:** the 3DS top screen is 400×240 (5:3) and maps were built for that camera. A 16:9
window shows more at the sides, which can expose map edges, missing geometry, or late pop-in.
Per map, in order of preference: leave as-is if it looks fine → fog/vignette the edges →
pillarbox to 5:3 → add filler geometry.

### Data flow

- Live state (positions, battles in progress) → game server memory
- Shared, short-lived state → Redis
- Permanent state → Postgres, saved on key events (catch, trade, battle end, logout) and on autosave
- Trades run inside a single Postgres transaction so Pokémon can never be duplicated

## First playable scope

Vaniville Town → Route 1 → Aquacorde Town. 3–4 wild species, one trainer. Full Kalos only
after the loop works end to end: walk, battle, catch, save, see other players.

## Roadmap

| Phase | Goal | Done when |
|---|---|---|
| 0. Asset spike | One Pokémon model + one town map from the RomFS into Godot — **by hand first** (SPICA/Ohana3DS → Blender → glTF), then automate in the importer | Garchomp stands in Vaniville Town, viewed at 16:9 with edge issues noted |
| 1. Overworld | Grid movement, camera, collision, map transitions | Walk from Vaniville through Route 1 to Aquacorde |
| 2. Multiplayer | Colyseus rooms, accounts, position sync | Two clients see each other walking |
| 3. Wild battles | Encounter tables, Showdown sim + catch/EXP/AI wrapper, battle UI | Catch a Pokémon and it saves |
| 4. Progression | NPCs, trainers, events, items, Pokémon Centers, gyms, Mega Evolution (Key Stone, Mega Stones, Mega button) | Earn badge 1; Lucario Mega Evolves |
| 5. Social | PvP, trading, friends, chat channels | Two players trade and battle |

Phase 0 is the biggest risk: if the asset pipeline doesn't work, nothing else matters.
Phase 2 can start in parallel with Phase 0, since the server doesn't depend on assets.

## Risks to check early

- **Colyseus + Godot:** no official Godot SDK; community ones may lag Godot 4. Check at the
  start of Phase 2. Fallback: plain WebSocket client with our own JSON messages.
- **Phase 3 size:** the battle wrapper (catching, EXP, evolution, AI) is bigger than it looks.

## Hosting

- **Now (free):** Postgres + Redis in Docker locally (`docker compose up -d`).
- **Friends testing (free):** Neon/Supabase + Upstash free tiers, or Tailscale to the dev PC.
- **Small launch (~$5–20/month):** one VPS (e.g. Hetzner) with daily backups.

## Decided

- Importer language: C# (reuse SPICA / Ohana3DS / pk3DS parsers).
- First playable scope: Vaniville → Route 1 → Aquacorde.
- Movement: grid-based.
- Story events: own format, not emulated X/Y scripts.
- Single screen: bottom-screen features become PC UI; own UI art, not extracted textures.

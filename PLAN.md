# Pokemon Mega MMO — Plan

An MMO set in the Kalos region (Pokémon X) with Mega Evolution, modeled on how PokeMMO works:
the game ships **no Nintendo assets**. Each player supplies their own Pokémon X data, and the
client loads graphics, maps and audio from it.

## Ground rules

- Never distribute ROMs, decryption keys, or extracted assets.
- Players provide a decrypted RomFS dumped from **their own** 3DS (GodMode9).
- The server is authoritative: clients render and send input, the server decides outcomes.

## Architecture

| Part | Tech | Job |
|---|---|---|
| `importer/` | TBD (C# or Python) | Reads the player's RomFS, unpacks GARC archives, converts models/textures/maps/audio into a local asset cache (glTF, PNG, OGG) |
| `client/` | Godot 4 | Renders the 3D world from the asset cache, UI, input |
| `server/` | Node.js + TypeScript, Colyseus, Pokémon Showdown sim | Rooms per map, movement sync, chat, battles (Gen 6 + Mega Evolution) |
| Database | PostgreSQL | Accounts, Pokémon, PC boxes, items, badges, friends, trades |
| Cache | Redis | Sessions, online players, chat, queues |

Reference tools to study for the importer: pk3DS (game data), SPICA / Ohana3DS (models), vgmstream (audio).

### Data flow

- Live state (positions, battles in progress) → game server memory
- Shared, short-lived state → Redis
- Permanent state → Postgres, saved on key events (catch, trade, battle end, logout) and on autosave
- Trades run inside a single Postgres transaction so Pokémon can never be duplicated

## Roadmap

| Phase | Goal | Done when |
|---|---|---|
| 0. Asset spike | One Pokémon model + one town map from the RomFS into Godot | Garchomp stands in Vaniville Town |
| 1. Overworld | Movement, camera, collision, map transitions | Walk from town to Route 2 |
| 2. Multiplayer | Colyseus rooms, accounts, position sync | Two clients see each other walking |
| 3. Wild battles | Encounter tables + Showdown sim on the server, battle UI | Catch a Pokémon and it saves |
| 4. Progression | NPCs, trainers, scripts, items, Pokémon Centers, gyms | Earn badge 1 |
| 5. Mega Evolution | Key Stone, Mega Stones, Mega button in battle | Lucario Mega Evolves |
| 6. Social | PvP, trading, friends, chat channels | Two players trade and battle |

Phase 0 is the biggest risk: if the asset pipeline doesn't work, nothing else matters.

## Hosting

- **Now (free):** Postgres + Redis in Docker locally (`docker compose up -d`).
- **Friends testing (free):** Neon/Supabase + Upstash free tiers, or Tailscale to the dev PC.
- **Small launch (~$5–20/month):** one VPS (e.g. Hetzner) with daily backups.

## Open decisions

- Scope for the first playable version: full Kalos, or one town + one route?
- Importer language.

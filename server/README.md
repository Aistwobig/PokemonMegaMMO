# Server

Authoritative game server: Colyseus rooms, Showdown battle sim, Postgres.

## Commands

```
npm install
cp .env.example .env     # optional; defaults match docker-compose.yml
npm run dev              # start with auto-restart on file changes (ws://localhost:2567)
npm run bot -- Ash       # headless test player that walks to Route 2 (server must be running)
npm run battle:demo      # one Gen 6 battle in the terminal: Lucario Mega Evolves vs a wild Fletchling
npm run test:auth        # end-to-end account/login checks (server must be running)
npm run db:migrate       # apply db/migrations (needs Postgres: docker compose up -d)
npm run typecheck
```

## Layout

```
src/index.ts           registers one room per map and starts the server
src/auth/              register/login routes, scrypt passwords, sessions, rate limits
src/rooms/MapRoom.ts   login check, movement, warps, grass encounters — all validated server-side
src/world/online.ts    one connection per trainer
src/rooms/state.ts     state synced to clients (players in the room)
src/world/maps.ts      loads data/maps, tile/warp/encounter helpers
src/world/transfers.ts warp tickets so clients can't choose where they arrive
src/battle/showdown.ts Showdown sim wrapper
src/db/pool.ts         Postgres pool + transaction helper
data/maps/*.json       hand-written map data (placeholders for now)
db/migrations/*.sql    database schema
```

## Accounts

HTTP on the same port (`http://localhost:2567`), JSON bodies:

| Request | Body | Response |
|---|---|---|
| `POST /auth/register` | `{ username, password, trainerName }` | `201 { token, trainer }` |
| `POST /auth/login` | `{ username, password }` | `200 { token, trainer }` |
| `POST /auth/logout` | header `Authorization: Bearer <token>` | `204` |
| `GET /auth/me` | header `Authorization: Bearer <token>` | `200 { trainer }` |

`trainer` is `{ name, mapId, x, y, facing }`. Errors are `{ error }` with 400 (invalid input),
401 (wrong login), 409 (username or trainer name taken) or 429 (rate limited).

- Usernames: 3–16 letters, digits or `_`, case-insensitive. Passwords: 8–128 characters, hashed with scrypt.
- Tokens last 30 days. Only their SHA-256 is stored.
- Rate limits: 10 logins per 15 min (per IP and per username), 30 register attempts per 15 min and
  5 new accounts per hour (per IP). Running the tests repeatedly hits these; start the server with
  `AUTH_RATE_LIMITS=off` for local testing only.
- A trainer can be online once. Logging in again closes the older connection with code `4001`.

## Client protocol

Log in first, set the token on the SDK (`client.auth.token = token`), then join the map in
`trainer.mapId` with `{ ticket? }`. Joining any other map without a warp ticket is refused (403).

| Direction | Message | Payload |
|---|---|---|
| client → server | `move` | `"up" \| "down" \| "left" \| "right"` |
| client → server | `battleEnd` | — (placeholder until Phase 3) |
| server → client | `warp` | `{ to, ticket }` — leave this room, join `to` with `{ ticket }` |
| server → client | `wildEncounter` | `{ species, level }` |

Synced state: `mapId`, `players` (map of sessionId → `{ name, x, y, facing }`).

## Not done yet

- Saving Pokémon, items and money (only position is saved so far)
- Battles in rooms (Showdown runs only in `battle:demo` so far)
- Redis (transfer tickets, rate limits and the online list are in memory, fine for one process)

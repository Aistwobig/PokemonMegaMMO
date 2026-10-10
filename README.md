# Pokemon Mega MMO

A fan MMO set in Kalos with Mega Evolution. Like PokeMMO, it contains no Nintendo assets;
players supply their own Pokémon X game data. See [PLAN.md](PLAN.md).

## Layout

```
client/     Godot 4 project
server/     Node.js + Colyseus + Showdown battle sim
importer/   Player's RomFS → local asset cache
```

## Local development

Requirements: Docker Desktop, Node.js LTS, Godot 4.

```
docker compose up -d
```

Starts PostgreSQL on port 5432 and Redis on port 6379.

```
cd server
npm install
npm run dev
```

Starts the game server on ws://localhost:2567. See [server/README.md](server/README.md).

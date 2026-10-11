# Hosting a server for friends

Players run the package (`package/build.ps1` → `dist/PokemonMegaMMO.zip`): they import their own
Pokémon X dump with `Import.bat`, start `Play.bat` and type your server's address on the login
screen. This page is about the server side.

## 1. Run the server for real players

On the hosting PC (Docker Desktop and Node.js installed):

```
docker compose up -d          # Postgres + Redis, reachable only from this PC
cd server
npm install
npm run db:migrate
npm start                     # listens on port 2567, all network interfaces
```

Don't set `AUTH_RATE_LIMITS=off` here: that's for running the tests. Keep this window open while
people play (or run it as a service).

## 2. Let players reach it

Pick one:

| Option | Good for | What to do | Address players type |
|---|---|---|---|
| Same Wi-Fi / LAN | friends in the same house | allow port 2567 in Windows Firewall (below) | your PC's local IP, e.g. `192.168.1.20` (`ipconfig` → IPv4 Address) |
| **Tailscale** (recommended) | friends anywhere, free, no router setup | install Tailscale on your PC and theirs, invite them to your tailnet (or share the machine); allow port 2567 in Windows Firewall | your PC's Tailscale IP, e.g. `100.101.102.103` (shown in the Tailscale app) |
| Port forwarding | anyone on the internet | forward TCP 2567 on your router to your PC; allow it in Windows Firewall | your public IP (or a dynamic DNS name) |
| A small VPS | always online, not your PC | e.g. a $5–10/month Linux VPS: install Docker + Node, clone the repo, steps 1–2 there, open port 2567 | the VPS's IP or domain |

Windows Firewall rule (PowerShell **as administrator**, once):

```
New-NetFirewallRule -DisplayName "Pokemon Mega MMO" -Direction Inbound -Protocol TCP -LocalPort 2567 -Action Allow
```

Check from another device: open `http://<address>:2567/auth/me` in a browser. A JSON error like
`{"error":"Not logged in."}` means the server is reachable.

## 3. Before opening it to strangers

- **Encryption.** The game talks plain HTTP/WebSocket, so passwords cross the network unencrypted.
  That's acceptable on a LAN or inside Tailscale (which encrypts everything). On the open internet,
  put a TLS proxy in front, e.g. [Caddy](https://caddyserver.com) with
  `play.example.com { reverse_proxy localhost:2567 }`, and have players type
  `https://play.example.com` (the client switches to secure WebSockets by itself).
- **Database.** `docker-compose.yml` binds Postgres and Redis to `127.0.0.1` only. Keep it that
  way, and change the database password (`POSTGRES_PASSWORD` there and `DATABASE_URL` in
  `server/.env`) on any machine others can reach.
- **Backups.** Everything players own is in the `pgdata` Docker volume. Back it up regularly, e.g.
  `docker compose exec postgres pg_dump -U game pokemmo > backup.sql`.
- **Updates.** Players need a matching client: when the server's maps or messages change, rebuild
  the package and send it again.

## 4. Building the package

```
powershell -ExecutionPolicy Bypass -File package\build.ps1
```

It needs `client\addons\colyseus` (from `client\tools\install-colyseus.ps1`), BchTool built next
to SPICA (`importer\BchTool\build.ps1`) and Godot 4.7.2. The zip holds no Nintendo files: the game
scripts, the Godot runtime, the importer and the two `.bat` files.

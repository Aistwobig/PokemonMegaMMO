# How PokeMMO is built (reference)

PokeMMO is closed-source and its developers have never published an architecture write-up.
This page collects what is publicly known, marks how reliable each point is, and notes what it
means for this project. Researched October 2026.

**Reliability labels**
- **Confirmed**: official PokeMMO page, or public code with PokeMMO's name on it
- **Community**: repeated by players or forum posts, never stated by the developers
- **Inference**: our reading of the confirmed facts

## The short version

PokeMMO is a **custom game engine that reads the player's own ROM for assets**, with an
**authoritative server** running the game rules. It is not an online emulator. This is the
same split as our plan ([PLAN.md](../PLAN.md)).

## What is known

| Area | What's known | Reliability |
|---|---|---|
| Client technology | Java. The official site requires a Java 17+ runtime. | Confirmed |
| Graphics/windowing | libGDX on LWJGL. PokeMMO has contributed to libGDX's native-build tooling (jnigen ARM support), which matches a libGDX desktop and Android client. | Confirmed (contributions), Community (engine choice) |
| Platforms | Windows, macOS, Linux, Android, iOS from one Java/libGDX codebase. | Confirmed (official downloads) |
| Origins (2012) | Started as a modified emulator (VisualBoyAdvance plus Pokémon FireRed) with multiplayer added. Prototype public around April–June 2012. | Community (dates disagree between sources) |
| Today's engine | Its own engine, not an emulator. Game mechanics re-implemented from scratch. | Community (consistent across many posts) |
| ROMs | Players supply their own ROMs (FireRed, Emerald, Platinum, HeartGold/SoulSilver, Black/White) through a "Client Management" screen. PokeMMO never distributes ROMs and says you must have the legal right to the ROM. | Confirmed (client and official stance) |
| What the ROM provides | Graphics, sprites, music, sound and text. **Not** game logic. | Community |
| Server | Holds the player's state and decides outcomes. Local edits are overwritten when state re-syncs, for example on area change. | Community (old posts. Exploits such as mail duplication were reported, so authority wasn't complete early on.) |
| Battles | Calculated server-side. | Inference (server authority plus anti-cheat) |
| 2026 native client | One third-party guide claims a 2026 update moved desktop to a native app without a separate Java runtime. | Unverified (conflicts with the official Java page) |

## How the pieces fit

**Inference**, based on the facts above:

```
Player's ROM ──► Client (Java/libGDX)                 Server (authoritative)
                  • reads sprites, maps, music,   ◄──►  • accounts, saves, party, items
                    text from the ROM at runtime         • movement validation, encounters
                  • draws the world and UI               • battle calculations
                  • sends input, renders results         • trading, chat, PvP, economy
```

- The client has the copyrighted assets only because the player provides them. The server has none.
- Rules come from the developers' own code and data tables, not from running the original game
  code. That's why PokeMMO can change things such as the EV system, PvP rules, events and
  multi-region travel, which an emulator can't do.
- Multiple regions in one world: each region uses its own ROM's assets, while one server and
  one player state cover all of them.

## Lessons for this project

| PokeMMO approach | Our version | Notes |
|---|---|---|
| Player supplies the ROM, nothing distributed | Player supplies a decrypted RomFS, and the importer builds a local asset cache | Same legal model. Also detect decryption by the data itself, not header flags (see Phase 0 findings). |
| Own engine, not an emulator | Godot 4 client | 3DS emulation would be far too heavy for an MMO anyway. |
| Server holds rules and state | Colyseus server + Showdown battle sim | Make the server authoritative from day one. PokeMMO's early exploits came from trusting the client. |
| Reads ROM assets at runtime | Converts once into an asset cache (glTF/PNG/OGG) | 3DS formats (BCH, GARC, LZ11) are too slow to parse on every load. |
| Mechanics re-implemented by hand | Showdown already implements Gen 6 mechanics | Saves the largest chunk of PokeMMO-style work. |
| 2D sprite games | 3D models (X/Y) | Harder: camera, edges outside the 3DS view, animations, transparency (see Phase 0). |

## Sources

- [PokeMMO: Java Runtime Environment (official)](https://pokemmo.com/en/java/)
- [libGDX PR #5556: jnigen armhf/aarch64 support by PokeMMO](https://github.com/libgdx/libgdx/pull/5556)
- [Raspberry Pi Forums: LibGDX on Buster (PokeMMO via LWJGL)](https://forums.raspberrypi.com/viewtopic.php?t=249098)
- [PCGamingWiki: PokeMMO](https://www.pcgamingwiki.com/wiki/PokeMMO)
- [PokeMMO forums: History of PokeMMO](https://forums.pokemmo.com/index.php?%2Ftopic%2F197967-history-of-pokemmo%2F=)
- [Baidu Baike: PokeMMO](https://baike.baidu.com/en/item/PokeMMO/1507785)
- [Hacker News discussion on PokeMMO and game assets](https://news.ycombinator.com/item?id=47825807)
- [elitepvpers: Does hacking the ROM hack PokeMMO?](https://www.elitepvpers.com/forum/pokemon/2130236-does-hacking-rom-you-use-pokemmo-hack-game-too.html)
- [Tech-Insider: PokeMMO setup guide 2026](https://tech-insider.org/pokemmo-setup-guide-2026/) (third-party, unverified claims)

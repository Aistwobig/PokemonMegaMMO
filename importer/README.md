# Importer

Turns the player's own Pokémon X RomFS into the client's asset cache (`client/asset-cache/`,
gitignored). Nothing produced here may be committed or shared.

For now these are manual steps; they become one `import` command later.

## Tools

- `BchTool/`: C# on SPICA.dll (BCH models/textures/motions → DAE + PNG). Build SPICA from source,
  then `BchTool/build.ps1` (writes `BchTool.exe` next to `SPICA.dll`).
- `tools/garc.py`: lists, dumps and splits GARC archives and the GF packs inside them.
- `tools/text.py`: decodes X/Y text files (game text and story text).
- `tools/tiles.py`: reads a map chunk's 40×40 tile grid.
- `tools/make_map.py`: builds a server map (walkable/blocked only) from map chunks.
- `tools/zone.py`: zone table and zone events (furniture, NPCs, warps, triggers).
- `tools/make_catalog.py`: builds `server/data/appearance.json` from the trainer manifests.

Python 3 (`py -3` on Windows). Below, `R` is the RomFS folder and `C` is `client/asset-cache`.

## Where things are in the RomFS

| GARC | Contents |
|---|---|
| `a/0/0/7` | Pokémon models |
| `a/0/1/2` | Zones: entry 360 = zone table; entry N = zone N's events (see `zone.py`). Zone 0 = the map01 overworld (Vaniville, Route 1, Aquacorde); zones 1–3 = the player's house |
| `a/0/1/3` | Area data; sub-file 11 (and 1) = the area's textures |
| `a/0/2/1` | Overworld characters, one "MM" pack each: 0 = model, 1 = motions. Entry N = `trNNNN` for 3–36 (tr0003 Shauna, tr0004 Tierno, tr0005 Trevor, tr0006 Sycamore, tr0007 Mom) |
| `a/0/4/1` | Map chunks, one "GR" pack each: 0 = tile grid, 1 = model, 2 = `coll` |
| `a/0/7/4` | English game text (100 = Sycamore's intro, 72 = location names) |
| `a/0/8/2` | English story text (55 = the player's house, 57 = the neighbors) |
| `a/0/8/8` | Player overworld clothing parts (girl 7–63, boy 397–432) |

Chunk models are centered: tile (x, y) covers model x ∈ [18x − 360, 18x − 342), likewise for z.
Grid values: `0x00000020` floor, `0x01000021` wall. Other values are special tiles (bed, PC,
bookshelf, ...); bit 0 set means solid. Stairs and doors aren't marked in the grid; they're zone
events. Warps store their position in world units (x, height, z ÷ 18 = global tile; Vaniville's
player-house door = tile 467, 596), triggers and furniture in global tiles. Global tile = chunk ×
40 + tile, with the chunk position from the zone's map matrix (map01: Vaniville = chunks (11,14)
and (11,15), so global (440, 560) is the town's top-left).

## Steps

**Text.** Exports every file as a JSON array of lines:

```
py -3 tools/text.py json R/a/0/7/4 C/text/game
py -3 tools/text.py json R/a/0/8/2 C/text/story
```

**Story characters.** For each id N (Sycamore = 6, Mom = 7):

```
py -3 tools/garc.py split R/a/0/2/1 N work/trN
BchTool export C/npc/tr000N tr000N work/trN/0.bch --motions work/trN/1.bin
```

**The player's house** (Vaniville, `t01r01`). GR 162 is the first floor, GR 163 the girl's
bedroom and GR 168 the boy's. Their textures are in area data 74 and 118:

```
py -3 tools/garc.py split R/a/0/4/1 162 work/gr162     (same for 163, 168)
py -3 tools/garc.py split R/a/0/1/3 74 work/ad74       (same for 118)
BchTool export C/maps/t01r01 house_1f   work/gr162/1.bch work/ad118/11.bch work/ad118/1.bch work/ad74/11.bch work/ad74/1.bch
BchTool export C/maps/t01r01 bedroom_f1 work/gr163/1.bch work/ad74/11.bch work/ad74/1.bch
BchTool export C/maps/t01r01 bedroom_f2 work/gr168/1.bch work/ad74/11.bch work/ad74/1.bch
py -3 tools/tiles.py json work/gr162/0.bin C/maps/t01r01/house_1f.tiles.json   (same for the bedrooms)
```

**Player trainers** (character customization), with `A` = a split of `a/0/8/8`:

```
BchTool parts C/trainers/f1 A/00008.bch <parts 9..63 and 7, minus 52 and 53> --textures <65..396> --motions <mm pack 1, sub-file 1>
BchTool parts C/trainers/f2 A/00398.bch <parts 399..432 and 397, minus 425 and 426> --textures <433..630> --motions <mm pack 2, sub-file 1>
py -3 tools/make_catalog.py
```

**Server town maps.** Walkable tiles only; spawn and warps in the file are kept by hand:

```
py -3 tools/make_map.py R/a/0/4/1 ../server/data/maps/vaniville.json --id vaniville --name "Vaniville Town" --chunks 12,14 --origin 440,560 --keep-meta ../server/data/maps/vaniville.json
```

**Dev views** for checking an export (Godot, from `client/`):

- `tests/npc_sheet.tscn [-- tr0006 ...]` shows every NPC in a grid.
- `tests/room_view.tscn -- t01r01/house_1f [x0 y0 x1 y1]` shows a room from above with its tile grid.

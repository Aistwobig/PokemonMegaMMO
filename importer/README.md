# Importer

Turns the player's own Pokémon X RomFS into the client's asset cache (`client/asset-cache/`,
gitignored). Nothing produced here may be committed or shared.

**One command does it all:** `BchTool import <romfs> <client/asset-cache>` (about 20 seconds, plus
about 3 minutes the first time for the soundtrack; the code is `BchTool/Importer.cs` and
`BchTool/Media.cs`). Players get it in the package as `Import.bat`. `--only <step>` runs just the
steps whose name contains that text (`--only icons`, `--only soundtrack`). The steps below are
what it does, and how to redo one by hand with the Python tools while working on the importer.

## Tools

- `BchTool/`: C# on SPICA.dll (BCH models/textures/motions → DAE + PNG). Build SPICA from source,
  then `BchTool/build.ps1` (writes `BchTool.exe` next to `SPICA.dll`).
- `tools/garc.py`: lists, dumps and splits GARC archives and the GF packs inside them.
- `tools/text.py`: decodes X/Y text files (game text and story text).
- `tools/tiles.py`: reads a map chunk's 40×40 tile grid.
- `tools/make_map.py`: builds a server map (walkable/blocked only) from map chunks.
- `tools/zone.py`: zone table and zone events (furniture, NPCs, warps, triggers).
- `tools/pokemon.py`: Pokémon models with their battle motions.
- `tools/make_catalog.py`: builds `server/data/appearance.json` from the trainer manifests.

Python 3 (`py -3` on Windows). Below, `R` is the RomFS folder and `C` is `client/asset-cache`.

## Where things are in the RomFS

| GARC | Contents |
|---|---|
| `a/0/0/7` | Pokémon models |
| `a/0/1/2` | Zones: entry 360 = zone table; entry N = zone N's events (see `zone.py`). Zone 0 = the map01 overworld (Vaniville, Route 1, Aquacorde); zones 1–3 = the player's house |
| `a/0/1/3` | Area data; sub-file 11 (and 1) = the area's textures |
| `a/0/2/1` | Overworld characters, one "MM" pack each: 0 = model, 1 = motions. Entry N = `trNNNN` for 3–36 (tr0003 Shauna, tr0004 Tierno, tr0005 Trevor, tr0006 Sycamore, tr0007 Mom) |
| `a/0/4/1` | Map chunks, one "GR" pack each: 0 = tile grid, 1 = model, 2 = `coll`. map01 = GR 0–15 |
| `a/0/4/2` | Map matrices: u32 0, u16 w, u16 h, then a GR id per chunk (0xFFFF = none). Matrix 0 = map01 |
| `a/0/7/4` | English game text (100 = Sycamore's intro, 72 = location names) |
| `a/0/8/2` | English story text (55 = the player's house, 57 = the neighbors) |
| `a/0/8/8` | Player overworld clothing parts (girl 7–63, boy 397–432) |

Chunk models are centered: tile (x, y) covers model x ∈ [18x − 360, 18x − 342), likewise for z.
Grid values: `0x00000020` floor, `0x01000021` wall, `0x20002004` tall grass. Other values are special tiles (bed, PC,
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

**Pokémon** (models, textures and battle motions; dex number:Showdown id). Each material's UV
transform and wrap mode goes into `<id>.materials.json`; the client applies them with a shader:

```
py -3 tools/pokemon.py R C/pokemon <BchTool.exe> 650:chespin 651:quilladin 653:fennekin 654:braixen 656:froakie 657:frogadier 661:fletchling 662:fletchinder 659:bunnelby 660:diggersby 664:scatterbug 665:spewpa 263:zigzagoon 264:linoone
```

Battle motions: 0 idle, 1 appear, 8 physical attack, 12 special attack, 16 hit, 17 faint.

**Pokémon icons** (`a/0/9/3`, 945 entries → `C/icons/<id>.png`, 40×30). Each entry is a BCLIM
whose data is X/Y's own palette format: u16 2, u16 color count, the colors (RGBA5551), then one
index per pixel (4 bits; 8 bits when there are more than 16 colors) in 8×8 Morton tiles over a
64×32 texture. The order is the game's internal Pokémon number (`pmNNNN`, the prefix of a model's
texture names; it equals the National Dex for Gen 1–5 but not for Kalos: Fennekin is pm0717,
Chespin pm0720), with every form side by side (Megas before the base form, Vivillon's 20 patterns,
Furfrou's trims, Pyroar ♂/♀). Entry 944 is the Egg. Not every form gets an icon (Pumpkaboo's
sizes share one, Venusaur ♀ has none) and a few species have a second copy (Clefairy, Greninja),
so the indices in `Importer.PokemonList` were checked by eye; check a new one the same way
(decode a range of entries into a contact sheet and look).

**Soundtrack** (`romfs/sound/*.aac` → `C/music/<name>.mp3`). The music is plain ADTS AAC (48 kHz
stereo, `bgm_xy_*` = music, `me_xy_*` = jingles). Godot can't play AAC, so Media Foundation
(built into Windows) decodes it and encodes 192 kb/s MP3. Which theme a map plays: the zone table
(`a/0/1/2` entry 360) has a music number at 0x08 (Vaniville 5, Route 1 11, Aquacorde 6, Route 2
12), an index into a table of `xy_sound.bcsar` sound IDs in `code.bin` at 0x44eacc: 5 = `T_01`,
6 = `T_02`, 11 = `R_A`, 12 = `R_B`. The client's `scripts/music.gd` has the map → track list.

**Tall grass** (`a/2/3/0`, a "TM" pack: grass00 = normal tall grass, 01–03 with flowers, 04 long
grass; each model has swaying animations). The client plants grass00 on every `0x20002004` tile:

```
py -3 tools/garc.py split R/a/2/3/0 0 work/grass
BchTool export C/npc/grass00 grass00 work/grass/7.bch work/grass/8.bch
```

Also export the overworld chunks' tile grids next to their models (the client reads them):
`py -3 tools/tiles.py json work/grN/0.bin C/maps/map01/map01_XX_YY.tiles.json`.

**Trainers.** Trainer data is `a/0/3/8` (20 bytes: format, class, ..., count; prize factor at byte 17)
and teams `a/0/4/0` (8 bytes per Pokémon: IV, ability, u16 level, u16 species, u16 form; +8 with
moves, +2 with items). Names: game text 21, classes: 20. `server/data/trainers.json` lists the ones
in use. Overworld trainer models (a/0/2/1): tr0100 Youngster, tr0104 Lass — export like the story
characters.

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

**The overworld** (map01: Vaniville, Route 1, Aquacorde, Route 2). Every chunk for the client,
with the overworld textures (area data 2):

```
py -3 tools/garc.py split R/a/0/1/3 2 work/ad2
for each GR 0..15:  py -3 tools/garc.py split R/a/0/4/1 N work/grN
                    BchTool export C/maps/map01 map01_XX_YY work/grN/1.bch work/ad2/11.bch work/ad2/1.bch
```

(XX_YY is the chunk name inside the BCH, e.g. GR 12 = `map01_11_14`.) And the server maps, cut
from the same grid by rows, with edge warps between neighbours (spawn and encounters are kept):

```
py -3 tools/make_map.py R ../server/data/maps --matrix 0 --cols 440,479   --map "vaniville:Vaniville Town:560:596-639" --map "route1:Route 1:552:553-595"   --map "aquacorde:Aquacorde Town:480:481-552" --map "route2:Route 2:440:440-480"
```

**Dev views** for checking an export (Godot, from `client/`):

- `tests/npc_sheet.tscn [-- tr0006 ...]` shows every NPC in a grid.
- `tests/room_view.tscn -- t01r01/house_1f [x0 y0 x1 y1]` shows a room from above with its tile grid.

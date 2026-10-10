"""Builds a server map (server/data/maps/<id>.json) from X/Y map chunks: only walkable/blocked
per tile, the one piece of map data the server needs (it never sees the ROM).

usage:
  make_map.py <a041 GARC> <out.json> --id vaniville --name "Vaniville Town" \
      --chunks 12,14 --origin 440,560 [--keep-meta <old.json>]

--chunks  GR entries stacked top to bottom (one column of 40-tile chunks)
--origin  global tile of the map's top-left in its X/Y map matrix (zone coordinates use these)
--keep-meta copies spawn, warps and encounters from an existing file (they're hand-written)
"""
import argparse
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(__file__))
from garc import read_garc, entry  # noqa: E402


def gr_grid(buf, ents, gr):
    pack = entry(buf, ents, gr)[0]
    count = struct.unpack_from("<H", pack, 2)[0]
    offs = struct.unpack_from("<%dI" % (count + 1), pack, 4)
    d = pack[offs[0]:offs[1]]
    w, h = struct.unpack_from("<HH", d, 0)
    tiles = struct.unpack_from("<%dI" % (w * h), d, 4)
    # Bit 0 set = solid (walls, furniture, water edges...). Everything else can be walked on.
    return ["".join("#" if tiles[y * w + x] & 1 else "." for x in range(w)) for y in range(h)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("garc")
    ap.add_argument("out")
    ap.add_argument("--id", required=True)
    ap.add_argument("--name", required=True)
    ap.add_argument("--chunks", required=True)
    ap.add_argument("--origin", required=True)
    ap.add_argument("--keep-meta")
    a = ap.parse_args()
    buf, ents = read_garc(a.garc)
    rows = []
    for gr in a.chunks.split(","):
        rows += gr_grid(buf, ents, int(gr))
    ox, oy = (int(v) for v in a.origin.split(","))
    data = {
        "_note": "Walkable tiles from the player's RomFS (importer/tools/make_map.py). Spawn and warps are hand-written.",
        "id": a.id,
        "name": a.name,
        "origin": {"x": ox, "y": oy},
        "tiles": rows,
        "spawn": {"x": 0, "y": 0},
        "warps": [],
        "encounterRate": 0,
        "encounters": [],
    }
    if a.keep_meta and os.path.exists(a.keep_meta):
        old = json.load(open(a.keep_meta, encoding="utf-8"))
        for k in ("spawn", "warps", "encounterRate", "encounters"):
            if k in old:
                data[k] = old[k]
    with open(a.out, "w", encoding="utf-8", newline="\n") as f:
        f.write("{\n")
        items = list(data.items())
        for i, (k, v) in enumerate(items):
            end = ",\n" if i < len(items) - 1 else "\n"
            if k == "tiles":
                f.write('  "tiles": [\n' + ",\n".join('    "%s"' % r for r in v) + "\n  ]" + end)
            else:
                f.write("  %s: %s%s" % (json.dumps(k), json.dumps(v), end))
        f.write("}\n")
    print("%s: %d x %d tiles" % (a.out, len(rows[0]), len(rows)))


if __name__ == "__main__":
    main()

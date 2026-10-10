"""Builds server maps (server/data/maps/<id>.json) from an X/Y overworld: walkable, blocked and tall
grass per tile, the one piece of map data the server needs (it never sees the ROM).

usage:
  make_map.py <romfs> <maps dir> --matrix 0 --cols 440,479 \
      --map vaniville:"Vaniville Town":560:595-639 \
      --map route1:"Route 1":552:553-595 ...

Each --map is id:name:origin_row:first-last. The map's file starts at origin_row (global tile rows
of the map matrix, 40 per chunk) and owns rows first..last; rows of the file outside that range
are blocked, except the row right above/below the owned range when another --map owns it: those
become edge warps to the same tile in that map, so neighbouring maps join seamlessly. Spawn and
encounters are kept from the existing file (they're hand-written); warps are regenerated.

Tiles: '.' walkable, '#' blocked (bit 0 set), 'G' tall grass (0x20002004).
"""
import argparse
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(__file__))
from garc import read_garc, entry  # noqa: E402

GRASS = 0x20002004


def pack_file(pack, i):
    count = struct.unpack_from("<H", pack, 2)[0]
    offs = struct.unpack_from("<%dI" % (count + 1), pack, 4)
    return pack[offs[i]:offs[i + 1]]


def gr_tiles(buf, ents, gr):
    d = pack_file(entry(buf, ents, gr)[0], 0)
    w, h = struct.unpack_from("<HH", d, 0)
    return w, list(struct.unpack_from("<%dI" % (w * h), d, 4))


def char(t):
    if t == GRASS:
        return "G"
    return "#" if t & 1 else "."


class Overworld:
    """Global tile grid of one map matrix (a/0/4/2): chunk (cx, cy) covers tiles cx*40.., cy*40.."""

    def __init__(self, romfs, matrix):
        mb, me = read_garc(os.path.join(romfs, "a/0/4/2"))
        m = pack_file(entry(mb, me, matrix)[0], 0)
        self.w, self.h = struct.unpack_from("<HH", m, 4)
        self.ids = struct.unpack_from("<%dH" % (self.w * self.h), m, 8)
        self.buf, self.ents = read_garc(os.path.join(romfs, "a/0/4/1"))
        self.cache = {}

    def tile(self, gx, gy):
        cx, cy = gx // 40, gy // 40
        if not (0 <= cx < self.w and 0 <= cy < self.h):
            return 0x01000021
        gr = self.ids[cy * self.w + cx]
        if gr == 0xFFFF:
            return 0x01000021
        if gr not in self.cache:
            self.cache[gr] = gr_tiles(self.buf, self.ents, gr)[1]
        return self.cache[gr][(gy % 40) * 40 + gx % 40]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("romfs")
    ap.add_argument("out_dir")
    ap.add_argument("--matrix", type=int, required=True)
    ap.add_argument("--cols", required=True)
    ap.add_argument("--map", action="append", required=True)
    a = ap.parse_args()
    world = Overworld(a.romfs, a.matrix)
    x0, x1 = (int(v) for v in a.cols.split(","))
    maps = []
    for spec in a.map:
        mid, name, origin, rows = spec.split(":")
        first, last = (int(v) for v in rows.split("-"))
        maps.append({"id": mid, "name": name, "origin": int(origin), "first": first, "last": last})

    def owner(gy):
        return next((m for m in maps if m["first"] <= gy <= m["last"]), None)

    for m in maps:
        end = m["last"] + 1 if owner(m["last"] + 1) else m["last"]
        rows, warps = [], []
        for gy in range(m["origin"], end + 1):
            other = owner(gy)
            row = ""
            for gx in range(x0, x1 + 1):
                t = world.tile(gx, gy)
                c = char(t)
                if other is m:
                    row += c
                elif other and gy in (m["first"] - 1, m["last"] + 1) and c != "#":
                    row += "."
                    warps.append({"x": gx - x0, "y": gy - m["origin"], "to": other["id"],
                                  "toX": gx - x0, "toY": gy - other["origin"]})
                else:
                    row += "#"
            rows.append(row)
        path = os.path.join(a.out_dir, m["id"] + ".json")
        old = json.load(open(path, encoding="utf-8")) if os.path.exists(path) else {}
        data = {
            "_note": "Tiles from the player's RomFS (importer/tools/make_map.py): rows %d-%d of the overworld, "
                     "edge rows warp to the neighbouring map. Spawn and encounters are hand-written." % (m["first"], m["last"]),
            "id": m["id"],
            "name": m["name"],
            "origin": {"x": x0, "y": m["origin"]},
            "tiles": rows,
            "spawn": old.get("spawn", {"x": 0, "y": 0}),
            "warps": warps,
            "encounterRate": old.get("encounterRate", 0),
            "encounters": old.get("encounters", []),
        }
        write(path, data)
        print("%s: %d x %d tiles, %d edge warps" % (path, len(rows[0]), len(rows), len(warps)))


def write(path, data):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("{\n")
        items = list(data.items())
        for i, (k, v) in enumerate(items):
            end = ",\n" if i < len(items) - 1 else "\n"
            if k == "tiles":
                f.write('  "tiles": [\n' + ",\n".join('    "%s"' % r for r in v) + "\n  ]" + end)
            elif k == "warps":
                f.write('  "warps": [\n' + ",\n".join("    " + json.dumps(w) for w in v) + "\n  ]" + end)
            else:
                f.write("  %s: %s%s" % (json.dumps(k), json.dumps(v), end))
        f.write("}\n")


if __name__ == "__main__":
    main()

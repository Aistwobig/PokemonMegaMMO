"""Tile grid of an X/Y map chunk (sub-file 0 of a GR pack in a/0/4/1).

usage:
  tiles.py show <gr.bin>             print the grid ('#' blocked, '.' walkable, letters = special)
  tiles.py json <gr.bin> <out.json>  write {width, height, tiles: [u32...]} row by row

Layout: u16 width, u16 height (40 x 40), then one u32 per tile. A chunk is 720 units square, so a
tile is 18 units; tile (x, y) covers model x in [18x, 18x+18) and z in [18y, 18y+18).
0x01000021 = blocked, 0x00000020 = walkable floor. Other values are tile behaviors (stairs, beds,
door mats, ...): the high byte is the behavior, bit 0 seems to mean "solid".
"""
import json
import struct
import sys

BLOCKED = 0x01000021
FLOOR = 0x00000020


def read(path):
    d = open(path, "rb").read()
    w, h = struct.unpack_from("<HH", d, 0)
    return w, h, list(struct.unpack_from("<%dI" % (w * h), d, 4))


def main():
    cmd, path = sys.argv[1], sys.argv[2]
    w, h, tiles = read(path)
    if cmd == "show":
        special = sorted({t for t in tiles if t not in (BLOCKED, FLOOR)})
        sym = {BLOCKED: "#", FLOOR: "."}
        sym.update({v: "ABCDEFGHIJKLMNOPQRSTUVWXYZ"[i % 26] for i, v in enumerate(special)})
        print({sym[v]: hex(v) for v in special})
        print("   " + "".join(str(x % 10) for x in range(w)))
        for y in range(h):
            row = "".join(sym[tiles[y * w + x]] for x in range(w))
            if row.strip("#"):
                print("%2d %s" % (y, row))
    elif cmd == "json":
        with open(sys.argv[3], "w") as f:
            json.dump({"width": w, "height": h, "tiles": tiles}, f)
    else:
        print(__doc__)


if __name__ == "__main__":
    main()

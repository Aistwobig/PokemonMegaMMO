"""X/Y zone event data (a/0/1/2): which zone is which map, and its furniture, NPCs and warps.

usage:
  zone.py list <a012> [name#]     zones with their map matrix and location name id
  zone.py show <a012> <zone>      entities of one zone
  zone.py json <a012> <zone>...   entities as JSON on stdout

Entry 360 = zone table, 0x38 bytes per zone: u16 @0x02 area data (textures), u16 @0x04 map
matrix (a/0/4/2), u16 @0x1C location name (game text 72). Entry N < 360 = zone N's files
("ZO" pack): 0 = its table record, 1 = entities, 2 = scripts.
Entities: u32 length, u8 counts (furniture, NPCs, warps, triggers, triggers), then records.
Coordinates are in tiles of the zone's map matrix (40 per chunk); for multi-chunk maps they run
across chunks (x = chunkX * 40 + tile).
"""
import json
import struct
import sys
import os

sys.path.insert(0, os.path.dirname(__file__))
from garc import read_garc, entry  # noqa: E402

SIZES = {"furniture": 0x14, "npcs": 0x30, "warps": 0x18, "triggers": 0x18, "triggers2": 0x18}


def pack_files(d):
    count = struct.unpack_from("<H", d, 2)[0]
    offs = struct.unpack_from("<%dI" % (count + 1), d, 4)
    return [d[offs[i]:offs[i + 1]] for i in range(count)]


def zone_table(buf, ents):
    zd = entry(buf, ents, 360)[0]
    out = []
    for z in range(len(zd) // 0x38):
        rec = zd[z * 0x38:(z + 1) * 0x38]
        out.append({"zone": z, "area": struct.unpack_from("<H", rec, 2)[0],
                    "matrix": struct.unpack_from("<H", rec, 4)[0],
                    "name": struct.unpack_from("<H", rec, 0x1C)[0]})
    return out


def entities(buf, ents, zone):
    f = pack_files(entry(buf, ents, zone)[0])[1]
    counts = list(f[4:9])
    pos = 0x0C  # u32 length, 5 counts, padding
    out = {}
    for (kind, size), n in zip(SIZES.items(), counts):
        recs = []
        for i in range(n):
            r = f[pos:pos + size]
            pos += size
            recs.append(_decode(kind, r))
        out[kind] = recs
    return out


def _decode(kind, r):
    u16 = lambda o: struct.unpack_from("<H", r, o)[0]
    if kind == "furniture":
        return {"script": u16(0), "x": u16(0x08), "y": u16(0x0A), "w": u16(0x0C), "h": u16(0x0E)}
    if kind == "npcs":
        return {"id": u16(0), "model": u16(2), "x": u16(0x24), "y": u16(0x26),
                "z": struct.unpack_from("<f", r, 0x28)[0], "raw": r.hex()}
    if kind == "warps":
        return {"toZone": u16(0), "toWarp": u16(2), "raw": r.hex()}
    return {"raw": r.hex()}


def main():
    cmd, path = sys.argv[1], sys.argv[2]
    buf, ents = read_garc(path)
    if cmd == "list":
        for z in zone_table(buf, ents):
            if len(sys.argv) < 4 or z["name"] == int(sys.argv[3]):
                print(z)
    elif cmd == "show":
        for kind, recs in entities(buf, ents, int(sys.argv[3])).items():
            print(kind, len(recs))
            for i, r in enumerate(recs):
                print("  %2d %s" % (i, r))
    elif cmd == "json":
        print(json.dumps({z: entities(buf, ents, int(z)) for z in sys.argv[3:]}, indent=1))


if __name__ == "__main__":
    main()

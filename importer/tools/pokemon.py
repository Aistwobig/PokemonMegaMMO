"""Exports Pokémon models with their battle motions from a/0/0/7 into the client's asset cache.

usage:
  pokemon.py <romfs> <asset-cache/pokemon> <BchTool.exe> <dex>:<showdown id> [...] [--shiny]

a/0/0/7 entry 0 is an index: 4 bytes per species at (dex - 1) * 4 = u16 model, u8 forms, u8 flags.
Each form has 8 entries starting at 4 + 8 * model: 0 model (PC pack: model BCH), 2 textures,
3 shiny textures, 5 animations (PB pack: file 0 is the GF motion pack of battle motions; the .bch
files are material/visibility animations such as blinking).
Writes <out>/<id>/<id>.dae, its textures and <id>_motNN.dae for each battle motion.
"""
import os
import struct
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(__file__))
from garc import read_garc, entry  # noqa: E402


def pack_files(d):
    count = struct.unpack_from("<H", d, 2)[0]
    offs = struct.unpack_from("<%dI" % (count + 1), d, 4)
    return [d[offs[i]:offs[i + 1]] for i in range(count)]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    shiny = "--shiny" in sys.argv
    romfs, out, bchtool = args[:3]
    buf, ents = read_garc(os.path.join(romfs, "a/0/0/7"))
    index = entry(buf, ents, 0)[0]
    with tempfile.TemporaryDirectory() as tmp:
        for spec in args[3:]:
            dex, name = spec.split(":")
            model = struct.unpack_from("<H", index, (int(dex) - 1) * 4)[0]
            base = 4 + 8 * model
            files = {}
            for key, k in (("model", 0), ("tex", 3 if shiny else 2), ("anim", 5)):
                data = entry(buf, ents, base + k)[0]
                inner = pack_files(data)[0]  # the first file of each pack
                path = os.path.join(tmp, "%s_%s.bin" % (name, key))
                open(path, "wb").write(inner)
                files[key] = path
            dest = os.path.join(out, name + ("_shiny" if shiny else ""))
            cmd = [bchtool, "export", dest, name, files["model"], files["tex"], "--motions", files["anim"]]
            res = subprocess.run(cmd, capture_output=True, text=True)
            print("%s (#%s): %s" % (name, dex, (res.stdout or res.stderr).strip().splitlines()[0] if (res.stdout or res.stderr) else "?"))


if __name__ == "__main__":
    main()

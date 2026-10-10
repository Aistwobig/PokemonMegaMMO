"""Gen 6 (X/Y) text file decoder.

usage:
  text.py dump <garc> <file#>             print every line of one text file
  text.py grep <garc> <regex>             find lines across all files of a GARC
  text.py json <garc> <outdir> [file#..]  write files as JSON arrays of lines (all if none given)

English text: a/0/7/4 = game text (menus, names), a/0/8/2 = story text (map scripts).
Variables are kept as tokens like [VAR 0100(0000)]; [VAR 0100] is the player's name.
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from garc import read_garc, entry  # noqa: E402

KEY_BASE = 0x7C89
KEY_ADVANCE = 0x2983


def decode_file(data):
    sections, count, _total, _initial_key, sdo = (
        int.from_bytes(data[0:2], "little"),
        int.from_bytes(data[2:4], "little"),
        int.from_bytes(data[4:8], "little"),
        int.from_bytes(data[8:12], "little"),
        int.from_bytes(data[12:16], "little"),
    )
    if sections != 1:
        raise ValueError("not a text file")
    lines = []
    key = KEY_BASE
    for i in range(count):
        entry = sdo + 4 + i * 8
        off = int.from_bytes(data[entry:entry + 4], "little") + sdo
        length = int.from_bytes(data[entry + 4:entry + 6], "little")
        chars = []
        k = key
        for j in range(length):
            c = int.from_bytes(data[off + j * 2:off + j * 2 + 2], "little") ^ k
            k = ((k << 3) | (k >> 13)) & 0xFFFF
            chars.append(c)
        lines.append(_render(chars))
        key = (key + KEY_ADVANCE) & 0xFFFF
    return lines


def _render(chars):
    out = []
    i = 0
    while i < len(chars):
        c = chars[i]
        i += 1
        if c == 0:
            break
        if c == 0x10:  # variable: count, code, args
            n = chars[i]
            code = chars[i + 1]
            args = chars[i + 2:i + 1 + n]
            i += 1 + n
            if code == 0xBE00:
                out.append("\\r")  # scroll
            elif code == 0xBE01:
                out.append("\\c")  # clear (next box)
            elif code == 0xBE02:
                out.append("[WAIT %d]" % (args[0] if args else 0))
            else:
                out.append("[VAR %04X%s]" % (code, "(" + ",".join("%04X" % a for a in args) + ")" if args else ""))
        elif c == 0xE000:
            out.append("\\n")
        elif c == 0x25BC:
            out.append("\\r")
        elif c == 0x25BD:
            out.append("\\c")
        elif c == 0xE07F:
            out.append(" ")
        elif c == 0xE08D:
            out.append("…")
        elif c == 0xE08E:
            out.append("♂")
        elif c == 0xE08F:
            out.append("♀")
        else:
            out.append(chr(c))
    return "".join(out)


def files(garc):
    """Yields (index, data) for every entry of a GARC."""
    buf, entries = read_garc(garc)
    for i in range(len(entries)):
        yield i, entry(buf, entries, i)[0]


def load(garc, index):
    buf, entries = read_garc(garc)
    return decode_file(entry(buf, entries, index)[0])


def main():
    cmd, garc = sys.argv[1], sys.argv[2]
    sys.stdout.reconfigure(encoding="utf-8")
    if cmd == "dump":
        for i, line in enumerate(load(garc, int(sys.argv[3]))):
            print("%4d  %s" % (i, line))
    elif cmd == "grep":
        pattern = re.compile(sys.argv[3], re.I)
        for f, raw in files(garc):
            try:
                lines = decode_file(raw)
            except (ValueError, IndexError):
                continue
            for i, line in enumerate(lines):
                if pattern.search(line):
                    print("%3d:%-4d %s" % (f, i, line))
    elif cmd == "json":
        out = sys.argv[3]
        os.makedirs(out, exist_ok=True)
        wanted = {int(a) for a in sys.argv[4:]}
        for f, raw in files(garc):
            if wanted and f not in wanted:
                continue
            try:
                lines = decode_file(raw)
            except (ValueError, IndexError):
                continue
            with open(os.path.join(out, "%d.json" % f), "w", encoding="utf-8") as fh:
                json.dump(lines, fh, ensure_ascii=False, indent=1)
    else:
        print(__doc__)


if __name__ == "__main__":
    main()

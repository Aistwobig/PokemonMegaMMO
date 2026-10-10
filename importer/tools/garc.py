"""Minimal GARC reader for Pokemon X/Y.

usage:
  garc.py info  <garc>                 summary + magic of first entries
  garc.py peek  <garc> <i> [<j> ...]   magic/size of entries (decompressed)
  garc.py dump  <garc> <outdir> [i..]  extract entries (all if none given)
  garc.py split <garc> <i> <outdir>    extract the files inside a GF pack entry (PC, PT, MM, ...)
"""
import os
import struct
import sys


def lz11_decompress(src):
    if src[0] != 0x11:
        raise ValueError("not LZ11")
    size = src[1] | (src[2] << 8) | (src[3] << 16)
    pos = 4
    if size == 0:
        size = struct.unpack_from("<I", src, 4)[0]
        pos = 8
    out = bytearray()
    while len(out) < size:
        flags = src[pos]
        pos += 1
        for bit in range(7, -1, -1):
            if len(out) >= size:
                break
            if not (flags >> bit) & 1:
                out.append(src[pos])
                pos += 1
                continue
            b0 = src[pos]
            ind = b0 >> 4
            if ind == 0:
                length = (((b0 & 0xF) << 4) | (src[pos + 1] >> 4)) + 0x11
                disp = ((src[pos + 1] & 0xF) << 8 | src[pos + 2]) + 1
                pos += 3
            elif ind == 1:
                length = (((b0 & 0xF) << 12) | (src[pos + 1] << 4) | (src[pos + 2] >> 4)) + 0x111
                disp = ((src[pos + 2] & 0xF) << 8 | src[pos + 3]) + 1
                pos += 4
            else:
                length = ind + 1
                disp = ((b0 & 0xF) << 8 | src[pos + 1]) + 1
                pos += 2
            start = len(out) - disp
            for k in range(length):
                out.append(out[start + k])
    return bytes(out)


def maybe_decompress(data):
    if len(data) > 4 and data[0] == 0x11:
        try:
            return lz11_decompress(data), True
        except (IndexError, ValueError):
            pass
    return data, False


def read_garc(path):
    with open(path, "rb") as f:
        buf = f.read()
    if buf[:4] != b"CRAG":
        raise ValueError("not a GARC")
    data_off = struct.unpack_from("<I", buf, 0x10)[0]
    fato_size = struct.unpack_from("<I", buf, 0x20)[0]
    count = struct.unpack_from("<H", buf, 0x24)[0]
    pos = 0x1C + fato_size
    assert buf[pos:pos + 4] == b"BTAF"
    pos += 12
    entries = []  # list of lists of (start, end)
    for _ in range(count):
        bits = struct.unpack_from("<I", buf, pos)[0]
        pos += 4
        subs = []
        for b in range(32):
            if bits >> b & 1:
                s, e, _len = struct.unpack_from("<III", buf, pos)
                pos += 12
                subs.append((data_off + s, data_off + e))
        entries.append(subs)
    return buf, entries


def magic(d):
    m = d[:4]
    txt = "".join(chr(c) if 32 <= c < 127 else "." for c in m)
    if d[:2] == b"PC" or d[:2] == b"PT" or d[:2] == b"PB":
        n = struct.unpack_from("<H", d, 2)[0]
        return f"{d[:2].decode()} pack ({n} files)"
    return txt


def entry(buf, entries, i, sub=0):
    s, e = entries[i][sub]
    return maybe_decompress(buf[s:e])


def main():
    cmd, path = sys.argv[1], sys.argv[2]
    buf, entries = read_garc(path)
    if cmd == "info":
        print(f"{path}: {len(entries)} entries")
        for i in range(min(12, len(entries))):
            d, c = entry(buf, entries, i)
            print(f"  [{i}] {len(d):>9} {'lz ' if c else '   '}{magic(d)}")
    elif cmd == "peek":
        for a in sys.argv[3:]:
            i = int(a)
            d, c = entry(buf, entries, i)
            extra = ""
            if d[:2] == b"PC":
                n = struct.unpack_from("<H", d, 2)[0]
                offs = struct.unpack_from(f"<{n + 1}I", d, 4)
                extra = " -> " + ", ".join(magic(d[offs[k]:offs[k + 1]]) or "-" for k in range(n))
            print(f"  [{i}] {len(d):>9} {'lz ' if c else '   '}{magic(d)}{extra}")
    elif cmd == "dump":
        out = sys.argv[3]
        os.makedirs(out, exist_ok=True)
        idx = [int(a) for a in sys.argv[4:]] or range(len(entries))
        for i in idx:
            d, _ = entry(buf, entries, i)
            ext = {b"BCH\0": ".bch", b"CGFX": ".cgfx"}.get(d[:4], ".bin")
            if d[:2] == b"PC":
                ext = ".pc"
            with open(os.path.join(out, f"{i:05d}{ext}"), "wb") as f:
                f.write(d)
        print(f"dumped {len(idx)} entries to {out}")
    elif cmd == "split":
        i, out = int(sys.argv[3]), sys.argv[4]
        d, _ = entry(buf, entries, i)
        n = struct.unpack_from("<H", d, 2)[0]
        offs = struct.unpack_from(f"<{n + 1}I", d, 4)
        os.makedirs(out, exist_ok=True)
        for k in range(n):
            sub = d[offs[k]:offs[k + 1]]
            ext = ".bch" if sub[:4] == b"BCH\0" else ".bin"
            with open(os.path.join(out, f"{k}{ext}"), "wb") as f:
                f.write(sub)
        print(f"{d[:2].decode()} pack with {n} files -> {out}")


if __name__ == "__main__":
    main()

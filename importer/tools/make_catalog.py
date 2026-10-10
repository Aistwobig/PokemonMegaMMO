"""Builds server/data/appearance.json from the trainer manifests BchTool writes.

The server never sees game files, but it must check that a chosen look only uses real parts and
colors. This keeps just the names: part ids, their category and their color codes.

usage: make_catalog.py <asset-cache/trainers> <server/data/appearance.json>
"""
import json
import os
import sys

GENDERS = {"f1": "girl", "f2": "boy"}


def main():
    trainers, out = sys.argv[1], sys.argv[2]
    catalog = {}
    for gender in GENDERS:
        with open(os.path.join(trainers, gender, "manifest.json"), encoding="utf8") as f:
            manifest = json.load(f)
        parts = {}
        for p in manifest["parts"]:
            # Some shoes carry an ankle strip of the legs mesh; its sock styles aren't shoe colors.
            mats = [m for m in p["materials"]
                    if p["category"] == "socks" or not m.get("stem", "").endswith("_socks_")]
            colors = sorted({v for m in mats for v in m["variants"]})
            parts[p["name"]] = {"category": p["category"], "colors": colors}
        catalog[gender] = {"label": GENDERS[gender], "parts": parts}
    with open(out, "w", encoding="utf8", newline="\n") as f:
        json.dump(catalog, f, indent=1, sort_keys=True)
        f.write("\n")
    print(f"wrote {out}: " + ", ".join(f"{g} {len(c['parts'])} parts" for g, c in catalog.items()))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Download CC0 texture sets and HDRIs from Poly Haven into assets/env/.

Usage:
    python3 tools/fetch_polyhaven.py            # everything in ASSETS
    python3 tools/fetch_polyhaven.py medieval_blocks_03   # a subset

Each texture set gets <id>_diffuse.jpg, <id>_normal.jpg (OpenGL normals) and
<id>_arm.jpg (R = ambient occlusion, G = roughness, B = metallic), all 2K.
"""
import json
import os
import sys
import urllib.request

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "env")
RES = "2k"
ASSETS = {
    # id: kind
    "medieval_blocks_03": "texture",   # main wall stone
    "castle_brick_07": "texture",      # towers
    "aerial_grass_rock": "texture",    # field
    "brown_mud_leaves_01": "texture",  # trampled ground near the wall
    "weathered_brown_planks": "texture",  # gate, hoardings
    "kloofendal_48d_partly_cloudy_puresky": "hdri",
}
MAPS = {"Diffuse": "diffuse", "nor_gl": "normal", "arm": "arm"}


def fetch(url, dest):
    if os.path.exists(dest):
        print("  exists", os.path.basename(dest))
        return
    print("  %s -> %s" % (url, os.path.relpath(dest, ROOT)))
    urllib.request.urlretrieve(url, dest)


def main(ids):
    os.makedirs(ROOT, exist_ok=True)
    for asset_id in ids:
        kind = ASSETS[asset_id]
        print(asset_id)
        with urllib.request.urlopen("https://api.polyhaven.com/files/" + asset_id) as r:
            files = json.load(r)
        if kind == "hdri":
            entry = files["hdri"][RES]["hdr"]
            fetch(entry["url"], os.path.join(ROOT, asset_id + ".hdr"))
            continue
        for src, suffix in MAPS.items():
            if src not in files:
                print("  (no %s map)" % src)
                continue
            entry = files[src][RES].get("jpg") or files[src][RES].get("png")
            ext = entry["url"].rsplit(".", 1)[-1]
            fetch(entry["url"], os.path.join(ROOT, "%s_%s.%s" % (asset_id, suffix, ext)))


if __name__ == "__main__":
    main(sys.argv[1:] or list(ASSETS))

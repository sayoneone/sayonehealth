#!/usr/bin/env python3
"""Write the SayoneHealth app icons (ARCHITECTURE.md §2.1, §8.2).

Pure Python (zlib + struct), no PIL. Produces one 1024x1024 RGB PNG (no alpha)
with a vertical blue gradient and a white anti-aliased drop, and writes it to
both asset catalogs together with their Contents.json files:

  iOS/App/Assets.xcassets/Contents.json
  iOS/App/Assets.xcassets/AppIcon.appiconset/{AppIcon.png,Contents.json}
  Watch/App/Assets.xcassets/Contents.json
  Watch/App/Assets.xcassets/AppIcon.appiconset/{AppIcon.png,Contents.json}

The output is deterministic, so re-running it produces no diff.
Usage: python3 scripts/make_icons.py [--root PATH]
"""
import argparse
import json
import math
import os
import struct
import zlib

SIZE = 1024
TOP = (0x5A, 0xC8, 0xFA)      # light sky blue
BOTTOM = (0x0A, 0x4F, 0xA8)   # deep blue
WHITE = (0xFF, 0xFF, 0xFF)

# Drop geometry: the convex hull of a circle and a tip point above it.
CX = SIZE / 2.0
CY = 610.0          # circle centre
R = 250.0           # circle radius
TIP_Y = 170.0       # tip of the drop
SUBROWS = 4         # vertical supersampling for anti-aliasing


def _drop_half_width(y):
    """Half-width of the drop on the horizontal line y (None if outside)."""
    d = CY - TIP_Y
    tangent_y = CY - R * R / d
    tangent_half = R * math.sqrt(1.0 - (R * R) / (d * d))
    if y < TIP_Y or y > CY + R:
        return None
    if y <= tangent_y:
        return (y - TIP_Y) / (tangent_y - TIP_Y) * tangent_half
    dy = y - CY
    return math.sqrt(max(0.0, R * R - dy * dy))


def _row_coverage(py):
    """Per-pixel drop coverage (0..1) for pixel row py."""
    cov = [0.0] * SIZE
    for s in range(SUBROWS):
        y = py + (s + 0.5) / SUBROWS
        hw = _drop_half_width(y)
        if hw is None or hw <= 0:
            continue
        left, right = CX - hw, CX + hw
        x0 = max(0, int(math.floor(left)))
        x1 = min(SIZE - 1, int(math.floor(right)))
        for px in range(x0, x1 + 1):
            # exact horizontal overlap of [px, px+1] with [left, right]
            overlap = min(px + 1.0, right) - max(float(px), left)
            if overlap > 0:
                cov[px] += overlap / SUBROWS
    return cov


def render_png():
    rows = []
    for py in range(SIZE):
        t = py / (SIZE - 1)
        bg = tuple(round(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3))
        cov = _row_coverage(py)
        row = bytearray([0])  # filter type 0 (None)
        for px in range(SIZE):
            a = min(1.0, cov[px])
            if a <= 0.0:
                row += bytes(bg)
            else:
                row += bytes(round(bg[i] * (1.0 - a) + WHITE[i] * a) for i in range(3))
        rows.append(bytes(row))
    raw = b"".join(rows)

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)  # 8-bit, colour type 2 = RGB
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def _write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    mode = "wb" if isinstance(data, bytes) else "w"
    kwargs = {} if isinstance(data, bytes) else {"encoding": "utf-8"}
    with open(path, mode, **kwargs) as f:
        f.write(data)


def _json(obj):
    return json.dumps(obj, indent=2, sort_keys=True) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--root", default=os.environ.get("SAYONE_REPO_ROOT")
                    or os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    args = ap.parse_args()

    png = render_png()
    catalog_info = {"info": {"author": "xcode", "version": 1}}
    for folder, platform in (("iOS/App", "ios"), ("Watch/App", "watchos")):
        cat = os.path.join(args.root, folder, "Assets.xcassets")
        iconset = os.path.join(cat, "AppIcon.appiconset")
        _write(os.path.join(cat, "Contents.json"), _json(catalog_info))
        _write(os.path.join(iconset, "AppIcon.png"), png)
        _write(os.path.join(iconset, "Contents.json"), _json({
            "images": [{"filename": "AppIcon.png", "idiom": "universal",
                        "platform": platform, "size": "1024x1024"}],
            "info": {"author": "xcode", "version": 1},
        }))
        print("wrote %s (%d bytes PNG, platform %s)" % (os.path.relpath(iconset, args.root), len(png), platform))


if __name__ == "__main__":
    main()

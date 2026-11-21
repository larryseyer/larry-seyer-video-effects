"""Find EEL2 compile errors in effects by rendering them in REAPER.

A Video Processor whose code fails to compile silently passes video through, so this
splits an effect into top-level blocks (separated by blank lines), renders progressively
longer prefixes that each end with a magenta marker square, and reports the first block
whose addition makes the marker disappear.

    python3 compile_check.py transform [color_grade ...]
"""
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vfx_render import EFFECTS, Fx, Item, Scene, Track, expand, render  # noqa: E402

SCRATCH = os.environ.get("LSVFX_OUT", "/tmp/lsvfx")
MARKER = ["gfx_dest = -1; gfx_mode = 0; gfx_set(1, 0, 1, 1); gfx_fillrect(0, 0, 240, 240);"]


def paren_delta(line, in_str):
    """Net parenthesis depth change of a line, ignoring // comments and string contents."""
    d = 0
    i = 0
    while i < len(line):
        ch = line[i]
        if in_str:
            if ch == '"':
                in_str = False
        elif ch == '"':
            in_str = True
        elif line.startswith("//", i):
            break
        elif ch == "(":
            d += 1
        elif ch == ")":
            d -= 1
        i += 1
    return d, in_str


def blocks(lines):
    """Split code into top-level blocks at blank lines where parentheses are balanced."""
    out, cur = [], []
    depth, in_str = 0, False
    for ln in lines:
        if not ln.strip() and cur and depth == 0 and not in_str:
            out.append(cur)
            cur = []
            continue
        cur.append(ln)
        d, in_str = paren_delta(ln, in_str)
        depth += d
    if cur:
        out.append(cur)
    return out


def has_marker(png):
    im = Image.open(png).convert("RGB")
    r, g, b = im.getpixel((4, 4))
    return r > 200 and g < 60 and b > 200


def check(effect):
    lines = expand(os.path.join(EFFECTS, effect + ".eel"))
    bl = blocks(lines)
    variants = []
    for k in range(1, len(bl) + 1):
        code = [ln for b in bl[:k] for ln in b] + MARKER
        variants.append(code)
    items = [Item("show.mp4", i*0.5, 0.5, takefx=[Fx(effect, {}, code=v)]) for i, v in enumerate(variants)]
    scene = Scene(tracks=[Track(items=items), Track(items=[Item("bars.mp4", 0, len(variants)*0.5)])])
    out = os.path.join(SCRATCH, "cc_" + effect)
    if os.path.isdir(out):
        for old in [f for f in os.listdir(out) if f.endswith(".png")]:
            os.remove(os.path.join(out, old))
    render(scene, out, [i*0.5 + 0.25 for i in range(len(variants))], tag="cc", cols=6, thumb_w=160)
    pngs = sorted(p for p in os.listdir(out) if p.startswith("cc_") and p[3:5].isdigit())
    for i, p in enumerate(pngs):
        if not has_marker(os.path.join(out, p)):
            first = bl[i]
            print(f"{effect}: FAILS at block {i + 1}/{len(bl)}:")
            print("\n".join("    " + ln for ln in first[:12]))
            return False
    print(f"{effect}: compiles")
    return True


if __name__ == "__main__":
    ok = all([check(e) for e in sys.argv[1:]])
    sys.exit(0 if ok else 1)

"""Renders one illustration per effect for docs/MANUAL.md, using each effect's first example.

    LSVFX_MEDIA=<folder with show.mp4 bars.mp4 blank.png logo.png green.png> python3 tools/render_doc_images.py [effect ...]

Reads docs/effects.json (run tools/build_docs.lua first), renders through REAPER with tests/vfx_render.py and
writes docs/images/<effect>.jpg.
"""
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tests"))
from vfx_render import Fx, Item, Scene, Track, render  # noqa: E402

OUT = os.path.join(ROOT, "docs", "images")
WORK = os.environ.get("LSVFX_OUT", "/tmp/lsvfx") + "/docimages"


def scene_for(e, params):
    """Builds a short scene that shows the effect the way it is meant to be used; returns (scene, time)."""
    stem = e["file"][:-4]
    fx = Fx(stem, params)
    text = None
    if e["examples"]:
        notes = e["examples"][0]["notes"]
        if 'Item name: "' in notes:
            text = notes.split('Item name: "')[1].split('"')[0]
    if e["category"] == "Transition":
        items = [Item("show.mp4", 0, 2.0, fadeout=1.0), Item("bars.mp4", 1.0, 2.0, fadein=1.0)]
        return Scene(tracks=[Track(items=items, fx=[fx])]), 1.5
    if stem in ("split_screen",):
        below = [Track(items=[Item("show.mp4", 0, 2, soffs=2)]), Track(items=[Item("bars.mp4", 0, 2)])]
        return Scene(tracks=[Track(items=[Item("show.mp4", 0, 2)], fx=[fx])] + below), 1.0
    if stem in ("blend", "green_screen"):
        top = "bars.mp4" if stem == "blend" else "green.png"
        return Scene(tracks=[Track(items=[Item(top, 0, 2)], fx=[fx]), Track(items=[Item("show.mp4", 0, 2)])]), 1.0
    if e["text"]:
        label = text or ("Title | Subtitle" if e["category"] == "Title" else "Energy Levels")
        length = max(4.0, params.get("dur", 0))
        item = Item("blank.png", 0, length, fadein=0.3, fadeout=0.3, name=label, takefx=[fx])
        return Scene(tracks=[Track(items=[item]), Track(items=[Item("show.mp4", 0, length)])]), \
            (length * 0.55 if stem == "credits" else 2.0)
    media = "logo.png" if stem == "place" and params.get("usealpha") else "show.mp4"
    item = Item(media, 0, 3, fadein=0.3 if stem in ("zoom_region", "spotlight", "magnifier", "place") else 0,
                takefx=[fx])
    return Scene(tracks=[Track(items=[item]), Track(items=[Item("bars.mp4", 0, 3)])]), 1.5


def main():
    with open(os.path.join(ROOT, "docs", "effects.json"), encoding="utf-8") as fh:
        effects = json.load(fh)["effects"]
    only = set(sys.argv[1:])
    os.makedirs(OUT, exist_ok=True)
    for e in effects:
        stem = e["file"][:-4]
        if only and stem not in only:
            continue
        params = dict(e["examples"][0]["set"]) if e["examples"] else {}
        if stem == "zoom_region":
            params["showbox"] = 0
        if stem == "credits":
            params["dur"] = 5      # keep the roll inside the 6 s sample clip
        sc, t = scene_for(e, params)
        if stem == "reframe":
            sc.width, sc.height = 1080, 1920   # shown as a vertical Short, its main use
        png = render(sc, WORK, [t], tag=stem, thumb_w=960 if sc.width >= sc.height else 400)
        jpg = os.path.join(OUT, stem + ".jpg")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", png, "-q:v", "4", jpg], check=True)
        print("image", stem)


if __name__ == "__main__":
    main()

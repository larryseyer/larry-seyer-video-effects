"""Renders the pictures for the website page (larryseyer.github.io, pages/projects/larry-seyer-video-effects.html).

    python3 tools/render_site_images.py <website images/projects folder> [effect ...]

Each picture is an effect over a plain gradient, never show footage or test patterns. Two 8-second gradient
clips stand in for show.mp4 and bars.mp4, so the scenes from tools/render_doc_images.py are reused unchanged.
Renders through REAPER in the test install (tests/vfx_render.py) and writes
larry-seyer-video-effects-<name>.webp (960x540) with cwebp.
"""
import json
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
sys.path.insert(0, os.path.join(ROOT, "tests"))
from render_doc_images import scene_for  # noqa: E402
from vfx_render import Fx, Item, Scene, Track, render  # noqa: E402

WORK = os.environ.get("LSVFX_OUT", "/tmp/lsvfx") + "/siteimages"
MEDIA = os.path.join(WORK, "media")

# effect -> website file name
SHOTS = {"callout": "callout", "lower_third": "lower-third", "border": "border", "tr_shape": "tr-shape",
         "title_card": "title-card", "multicam": "multicam"}

# The callout's own example points at a small control in show footage; over a gradient it needs to be larger.
OVERRIDES = {"callout": dict(bx=0.16, by=0.32, bw=0.32, bh=0.36, lx=0.72, ly=0.5, size=0.055, thick=0.004),
             "multicam": dict(layout=2, cam=1, camb=4)}

# Text shown by the title-style effects in place of their examples' item names.
LABELS = {"callout": "Call Outs"}

# Four cameras for the multicam shot: a 2x2 multiview whose quarters are four different gradients.
CAMERAS = ["c0=0x0e2238:c1=0x1f7a80", "c0=0x3b1a45:c1=0xd0813a", "c0=0x1d1442:c1=0x7b5cc4",
           "c0=0x0f2e22:c1=0x4fae7c"]

GRADIENTS = {"show.mp4": "c0=0x0e2238:c1=0x1f7a80:x0=0:y0=1080:x1=1920:y1=0",     # navy to teal
             "bars.mp4": "c0=0x3b1a45:c1=0xd0813a:x0=0:y0=0:x1=1920:y1=1080"}     # plum to amber


def make_media():
    """Writes the two gradient clips, the four-camera multiview and a transparent PNG for title items."""
    os.makedirs(MEDIA, exist_ok=True)
    for name, spec in GRADIENTS.items():
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
                        f"gradients=s=1920x1080:{spec}:r=30:d=8:n=2:speed=0:seed=1",
                        "-c:v", "libx264", "-pix_fmt", "yuv420p", os.path.join(MEDIA, name)], check=True)
    quarters = []
    for spec in CAMERAS:
        quarters += ["-f", "lavfi", "-i", f"gradients=s=960x540:{spec}:x0=0:y0=540:x1=960:y1=0:r=30:d=8:n=2:speed=0:seed=1"]
    subprocess.run(["ffmpeg", "-v", "error", "-y", *quarters, "-filter_complex",
                    "[0][1][2][3]xstack=inputs=4:layout=0_0|w0_0|0_h0|w0_h0", "-c:v", "libx264",
                    "-pix_fmt", "yuv420p", os.path.join(MEDIA, "multiview.mp4")], check=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "color=c=black@0:s=64x36,format=rgba",
                    "-frames:v", "1", os.path.join(MEDIA, "blank.png")], check=True)


def main():
    if len(sys.argv) < 2 or not os.path.isdir(sys.argv[1]):
        sys.exit(__doc__)
    if not shutil.which("cwebp"):
        sys.exit("cwebp not found (brew install webp)")
    dest = sys.argv[1]
    only = sys.argv[2:] or list(SHOTS)
    with open(os.path.join(ROOT, "docs", "effects.json"), encoding="utf-8") as fh:
        effects = {e["file"][:-4]: e for e in json.load(fh)["effects"]}
    make_media()
    for stem in only:
        e = effects[stem]
        params = dict(e["examples"][0]["set"]) if e["examples"] else {}
        params.update(OVERRIDES.get(stem, {}))
        if stem == "multicam":
            sc, t = Scene(tracks=[Track(items=[Item("multiview.mp4", 0, 3, takefx=[Fx(stem, params)])])]), 1.5
        else:
            sc, t = scene_for(e, params)
        if stem in LABELS:
            sc.tracks[0].items[0].name = LABELS[stem]
        png = render(sc, WORK, [t], tag=stem, media_dir=MEDIA, thumb_w=960)
        out = os.path.join(dest, f"larry-seyer-video-effects-{SHOTS[stem]}.webp")
        subprocess.run(["cwebp", "-quiet", "-q", "85", png, "-o", out], check=True)
        print("image", out)


if __name__ == "__main__":
    main()

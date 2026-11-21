"""Render one effect with several parameter sets and print the contact-sheet path.

    python3 run_effect.py <effect> '<json list of param dicts>' [--mode take|track]
        [--media show.mp4] [--bg bars.mp4] [--seg 1.0] [--at 0.5] [--fades in,out] [--name text]

take mode: each parameter set becomes a separate item carrying the effect as take FX,
           over a background track (--bg) so layer effects can show what is beneath.
track mode: one item per parameter set on a track, effect params driven by stepped envelopes.
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vfx_render import Fx, Item, Scene, Track, render  # noqa: E402

SCRATCH = os.environ.get("LSVFX_OUT", "/tmp/lsvfx")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("effect")
    ap.add_argument("params")
    ap.add_argument("--mode", default="take")
    ap.add_argument("--media", default="show.mp4")
    ap.add_argument("--bg", default="bars.mp4")
    ap.add_argument("--seg", type=float, default=1.0)
    ap.add_argument("--at", type=float, default=0.5)
    ap.add_argument("--fades", default="0,0")
    ap.add_argument("--name", default=None)
    ap.add_argument("--cols", type=int, default=3)
    ap.add_argument("--size", default="1920x1080")
    ap.add_argument("--tag", default=None)
    a = ap.parse_args()
    sets = json.loads(a.params)
    fin, fout = (float(x) for x in a.fades.split(","))
    w, h = (int(x) for x in a.size.split("x"))
    n = len(sets)
    tracks = []
    if a.mode == "take":
        items = [Item(a.media, i*a.seg, a.seg, soffs=i*a.seg % 5, fadein=fin, fadeout=fout,
                      name=a.name, takefx=[Fx(a.effect, p)]) for i, p in enumerate(sets)]
        tracks.append(Track(name="FX", items=items))
    else:
        items = [Item(a.media, 0, n*a.seg, name=a.name)]
        env = {}
        for i, p in enumerate(sets):
            for k, v in p.items():
                env.setdefault(k, []).append((i*a.seg, v, 1))
        tracks.append(Track(name="FX", items=items, fx=[Fx(a.effect, {}, envelopes=env)]))
    if a.bg:
        tracks.append(Track(name="BG", items=[Item(a.bg, 0, n*a.seg)]))
    times = [i*a.seg + a.at for i in range(n)]
    sheet = render(Scene(tracks=tracks, width=w, height=h), SCRATCH, times,
                   tag=a.tag or a.effect, cols=a.cols)
    print(sheet)


if __name__ == "__main__":
    main()

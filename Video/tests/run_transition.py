"""Render a transition effect across item crossfades, one crossfade per style value.

    python3 run_transition.py tr_push '[{"style":0,"dir":0},{"style":3}]' [--tag name]
Each parameter set gets its own A->B crossfade (1 s long); frames at 25/50/75 % are stacked per row.
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vfx_render import Fx, Item, Scene, Track, render  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("effect")
ap.add_argument("params")
ap.add_argument("--tag", default=None)
a = ap.parse_args()
sets = json.loads(a.params)
items, env, times = [], {}, []
for i, p in enumerate(sets):
    t0 = i*3.0
    items.append(Item("show.mp4", t0, 2.0, fadeout=1.0))
    items.append(Item("bars.mp4", t0 + 1.0, 2.0, fadein=1.0))
    for k, v in p.items():
        env.setdefault(k, []).append((t0, v, 1))
    times += [t0 + 1.25, t0 + 1.5, t0 + 1.75]
scene = Scene(tracks=[Track(items=items, fx=[Fx(a.effect, {}, envelopes=env)])])
print(render(scene, os.environ.get("LSVFX_OUT", "/tmp/lsvfx"), times, tag=a.tag or a.effect, cols=3, thumb_w=400))

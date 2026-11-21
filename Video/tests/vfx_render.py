"""Headless render harness for Larry Seyer Video Effects.

Builds a throwaway REAPER project containing video items and Video Processor
instances (track FX or take FX) whose code comes from the effects/*.eel files,
renders it with `REAPER -renderproject`, and extracts frames into a contact
sheet so effect output can be inspected without opening REAPER.

Usage from Python:
    from vfx_render import Scene, Track, Item, Fx, render
    scene = Scene(tracks=[Track(items=[Item('show.mp4', 0, 4)], fx=[Fx('color_grade', {...})])])
    render(scene, out_dir, times=[0.5, 1.5])
"""
import base64
import os
import re
import struct
import subprocess
import time
import uuid
from dataclasses import dataclass, field

HERE = os.path.dirname(os.path.abspath(__file__))
PACK = os.path.dirname(HERE)
EFFECTS = os.path.join(PACK, "effects")
# Tests only ever run in the isolated test install ~/ReaperTest (outside Dropbox, its own settings). It is started
# as a separate instance, so it never touches the REAPER you are working in or any other REAPER folder.
TEST_ROOT = os.path.expanduser("~/ReaperTest")
REAPER_BIN = os.path.join(TEST_ROOT, "REAPER.app/Contents/MacOS/REAPER")


INCLUDE = re.compile(r'^\s*//\s*#include\s+"([^"]+)"\s*$')


def expand(path, seen=None):
    """Read an effect file, inlining `// #include "lib/x.eel"` lines (paths relative to effects/)."""
    seen = seen or set()
    out = []
    with open(path, encoding="utf-8") as fh:
        for ln in fh.read().splitlines():
            m = INCLUDE.match(ln)
            if m:
                inc = os.path.join(EFFECTS, m.group(1))
                if inc not in seen:
                    seen.add(inc)
                    out += expand(inc, seen)
            else:
                out.append(ln)
    return out


def load_effect(name):
    """Return (code_lines, defaults) for effects/<name>.eel; defaults maps param index -> value."""
    path = name if name.endswith(".eel") else os.path.join(EFFECTS, name + ".eel")
    lines = expand(path)
    return lines, parse_defaults(lines)


def parse_defaults(lines):
    """Map param index -> default value from //@paramN:var 'label' default ... lines."""
    defaults = {}
    for ln in lines:
        m = re.match(r"\s*//@param\s*(\d+)\s*:\s*([\w.]+)\s+('[^']*'|\"[^\"]*\"|\S+)\s*(.*)", ln)
        if m:
            nums = m.group(4).split()
            defaults[int(m.group(1))] = float(nums[0]) if nums else 0.0
    return defaults


def param_index(lines, varname):
    for ln in lines:
        m = re.match(r"\s*//@param\s*(\d+)\s*:\s*([\w.]+)", ln)
        if m and m.group(2) == varname:
            return int(m.group(1))
    raise KeyError(varname)


@dataclass
class Fx:
    effect: str                      # effects/<effect>.eel, or raw code via `code`
    params: dict = field(default_factory=dict)   # varname -> value
    code: list = None
    envelopes: dict = field(default_factory=dict)  # varname -> [(time, value, shape)]

    def chunk(self, tag_indent):
        if self.code is not None:
            lines, defaults = self.code, parse_defaults(self.code)
        else:
            lines, defaults = load_effect(self.effect)
        vals = [0.0] * 40
        for idx, v in defaults.items():
            if 1 <= idx <= 40:
                vals[idx - 1] = v
        for var, v in self.params.items():
            vals[param_index(lines, var) - 1] = float(v)
        ind = " " * tag_indent
        out = [f'{ind}<VIDEO_EFFECT "Video processor" ""', f"{ind}  <CODE"]
        out += [f"{ind}    |{ln}" for ln in lines]
        out += [f"{ind}  >", f"{ind}  CODEPARM " + " ".join(repr(v) for v in vals), f"{ind}>"]
        out += [f"{ind}FLOATPOS 0 0 0 0", f"{ind}FXID {{{str(uuid.uuid4()).upper()}}}"]
        for var, pts in self.envelopes.items():
            # PARMENV param index is zero-based; Video processor param N is index N-1.
            idx = param_index(lines, var) - 1
            out.append(f"{ind}<PARMENV {idx} -1000000 1000000 0")
            out += [f"{ind}  ACT 1 -1", f"{ind}  VIS 0 1 1", f"{ind}  ARM 0", f"{ind}  DEFSHAPE 0 -1 -1"]
            out += [f"{ind}  PT {t} {v} {shape}" for (t, v, shape) in pts]
            out.append(f"{ind}>")
        out.append(f"{ind}WAK 0 0")
        return out


@dataclass
class Item:
    file: str = None                 # None = empty item (generator)
    pos: float = 0.0
    length: float = 4.0
    soffs: float = 0.0
    fadein: float = 0.0
    fadeout: float = 0.0
    name: str = None
    takefx: list = field(default_factory=list)

    def chunk(self, media_dir):
        nm = self.name or (os.path.basename(self.file) if self.file else "")
        out = ["    <ITEM", f"      POSITION {self.pos}", f"      LENGTH {self.length}", "      LOOP 0",
               f"      FADEIN 1 {self.fadein} 0 1 0 0 0", f"      FADEOUT 1 {self.fadeout} 0 1 0 0 0",
               f"      IGUID {{{str(uuid.uuid4()).upper()}}}", f'      NAME "{nm}"',
               f"      SOFFS {self.soffs}", "      PLAYRATE 1 1 0 -1 0 0.0025",
               f"      GUID {{{str(uuid.uuid4()).upper()}}}"]
        if self.file:
            path = self.file if os.path.isabs(self.file) else os.path.join(media_dir, self.file)
            out += ["      <SOURCE VIDEO", f'        FILE "{path}"', "      >"]
        if self.takefx:
            out += ["      <TAKEFX", "        SHOW 0", "        LASTSEL 0", "        DOCKED 0"]
            for fx in self.takefx:
                out.append("        BYPASS 0 0 0")
                out += fx.chunk(8)
            out.append("      >")
        out.append("    >")
        return out


@dataclass
class Track:
    items: list = field(default_factory=list)
    fx: list = field(default_factory=list)
    name: str = "T"

    def chunk(self, media_dir):
        out = [f"  <TRACK {{{str(uuid.uuid4()).upper()}}}", f'    NAME "{self.name}"', "    NCHAN 2",
               "    MAINSEND 1 0"]
        if self.fx:
            out += ["    <FXCHAIN", "      SHOW 0", "      LASTSEL 0", "      DOCKED 0"]
            for fx in self.fx:
                out.append("      BYPASS 0 0 0")
                out += fx.chunk(6)
            out.append("    >")
        for it in self.items:
            out += it.chunk(media_dir)
        out.append("  >")
        return out


@dataclass
class Scene:
    tracks: list
    width: int = 1920
    height: int = 1080
    vflags: int = 65792      # VIDEO_CONFIG flags; 67328 is what some user projects carry
    fps: float = 30.0
    tempo: float = 120.0
    length: float = None   # render length; defaults to end of last item


def render_cfg(w, h, fps):
    raw = b"FVAX" + struct.pack("<10i", 0, 0, 20000, 0, 320, w, h, 0, 1, 95) + b"\0\0"
    raw = raw[:32] + struct.pack("<f", fps) + raw[36:]
    return base64.b64encode(raw).decode()


def build_rpp(scene, media_dir, out_file):
    end = scene.length or max(it.pos + it.length for t in scene.tracks for it in t.items)
    lines = ['<REAPER_PROJECT 0.1 "7.86/macOS-arm64" 0 0',
             f"  VIDEO_CONFIG {scene.width} {scene.height} {scene.vflags}",
             f"  TEMPO {scene.tempo} 4 4",
             f'  RENDER_FILE "{out_file}"', "  RENDER_FMT 0 2 0",
             f"  RENDER_RANGE 0 0 {end} 0 1000", "  RENDER_RESAMPLE 9 9 1", "  RENDER_ADDTOPROJ 0",
             "  SAMPLERATE 48000 1 0", "  <RENDER_CFG", "    " + render_cfg(scene.width, scene.height, scene.fps),
             "  >", f"  SELECTION 0 {end}", f"  SELECTION2 0 {end}"]
    for t in scene.tracks:
        lines += t.chunk(media_dir)
    lines.append(">")
    return "\n".join(lines) + "\n"


def wait_for_reaper_exit(limit=30.0):
    """Waits for the previous test instance to quit before starting the next."""
    end = time.time() + limit
    while time.time() < end:
        if subprocess.run(["pgrep", "-f", REAPER_BIN], stdout=subprocess.DEVNULL).returncode != 0:
            return
        time.sleep(0.25)


def playable(mp4):
    if not os.path.exists(mp4):
        return False
    return subprocess.run(["ffprobe", "-v", "error", mp4], stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL).returncode == 0


def check_test_install():
    """Refuse to run anything but the isolated test install."""
    if not (os.path.isfile(REAPER_BIN) and os.path.isfile(os.path.join(TEST_ROOT, "reaper.ini"))):
        raise RuntimeError("test install missing: expected a portable REAPER in " + TEST_ROOT)


def run_script(lua_path, timeout=120):
    """Runs a ReaScript in the test install. The script must quit REAPER when done (Main_OnCommand(40004, 0)) after
    saving or leaving its project unmodified."""
    check_test_install()
    wait_for_reaper_exit()
    subprocess.run([REAPER_BIN, "-newinst", "-nosplash", lua_path], timeout=timeout,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    wait_for_reaper_exit()


def render(scene, out_dir, times, tag="run", media_dir=None, cols=None, thumb_w=640, timeout=240):
    """Render the scene in the test install and return the path of a contact sheet of frames at `times`."""
    check_test_install()
    os.makedirs(out_dir, exist_ok=True)
    media_dir = media_dir or os.environ.get("LSVFX_MEDIA", "")
    mp4 = os.path.join(out_dir, f"{tag}.mp4")
    rpp = os.path.join(out_dir, f"{tag}.RPP")
    if os.path.exists(mp4):
        os.remove(mp4)
    with open(rpp, "w", encoding="utf-8") as fh:
        fh.write(build_rpp(scene, media_dir, mp4))
    t0 = time.time()
    for attempt in range(3):
        if os.path.exists(mp4):
            os.remove(mp4)
        wait_for_reaper_exit()
        subprocess.run([REAPER_BIN, "-newinst", "-nosplash", "-renderproject", rpp], timeout=timeout,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        wait_for_reaper_exit()
        if playable(mp4):
            break
    else:
        raise RuntimeError(f"render produced no playable file for {tag} ({time.time() - t0:.1f}s)")
    frames = []
    for i, t in enumerate(times):
        png = os.path.join(out_dir, f"{tag}_{i:02d}.png")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", str(t), "-i", mp4, "-frames:v", "1",
                        "-vf", f"scale={thumb_w}:-2", png], check=True)
        frames.append(png)
    cols = cols or min(len(frames), 3)
    rows = (len(frames) + cols - 1) // cols
    sheet = os.path.join(out_dir, f"{tag}_sheet.png")
    inputs = []
    for f in frames:
        inputs += ["-i", f]
    if len(frames) == 1:
        os.replace(frames[0], sheet)
        return sheet
    layout = "|".join(f"{(i % cols) * thumb_w}_{'+'.join(['h0'] * (i // cols)) or 0}"
                      for i in range(len(frames)))
    subprocess.run(["ffmpeg", "-v", "error", "-y", *inputs, "-filter_complex",
                    f"xstack=inputs={len(frames)}:layout={layout}:fill=gray", sheet], check=True)
    return sheet

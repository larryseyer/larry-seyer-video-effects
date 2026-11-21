"""Builds the ReaPack repository index (index.xml) for Larry Seyer Video Effects.

    python3 tools/build_reapack_index.py [--commit <sha>] [--changelog "text"]

The pack lives in a folder of the repository (Video/); that folder name is the ReaPack category and the index is
written to the repository root. Release steps: bump `@version` in the main script, run tools/build_docs.lua,
commit and push, then run this script (it pins every file URL to the pushed commit), commit and push index.xml.
Earlier versions already in index.xml are kept so users can roll back.
"""
import argparse
import datetime
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from urllib.parse import quote

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # the pack folder (Video/ in the repo)
REPO_ROOT = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=ROOT, capture_output=True, text=True,
                           check=True).stdout.strip()
INDEX = os.path.join(REPO_ROOT, "index.xml")
CATEGORY = os.path.relpath(ROOT, REPO_ROOT)                            # ReaPack category = folder name
MAIN = "Larry Seyer Video Effects.lua"
ACTIONS = ["Larry Seyer Video Effects - Install or update presets.lua"]
PACKAGED_DIRS = ["lib", "effects", "ai"]
PACKAGED_FILES = ["LS Title Carrier.png", "README.md", "LICENSE", "docs/AI-REFERENCE.md", "docs/MANUAL.md",
                  "docs/effects.json"]


def conf():
    out = {}
    with open(os.path.join(ROOT, "tools", "release.conf"), encoding="utf-8") as fh:
        for line in fh:
            if "=" in line:
                k, v = line.split("=", 1)
                out[k.strip()] = v.strip()
    return out


def header(field):
    with open(os.path.join(ROOT, MAIN), encoding="utf-8") as fh:
        m = re.search(r"@" + field + r"\s+(.+)", fh.read())
    if not m:
        sys.exit(f"{MAIN} has no @{field} header")
    return m.group(1).strip()


def packaged_files():
    files = list(PACKAGED_FILES)
    for d in PACKAGED_DIRS:
        for base, _, names in os.walk(os.path.join(ROOT, d)):
            for n in sorted(names):
                if not n.startswith("."):
                    files.append(os.path.relpath(os.path.join(base, n), ROOT))
    missing = [f for f in files if not os.path.exists(os.path.join(ROOT, f))]
    if missing:
        sys.exit("missing packaged files: " + ", ".join(missing))
    return sorted(set(files))


def tracked_and_clean(files):
    """Every packaged file must be committed, or the pinned URLs would not serve it."""
    dirty = subprocess.run(["git", "status", "--porcelain", "--", MAIN, *ACTIONS, *files], cwd=ROOT,
                           capture_output=True, text=True).stdout.strip()
    if dirty:
        sys.exit("commit these first:\n" + dirty)


def rtf(text):
    body = text.replace("\\", "\\\\").replace("{", "\\{").replace("}", "\\}").replace("\n", "\\par\n")
    return "{\\rtf1\\ansi\\deff0{\\fonttbl{\\f0 \\fswiss Helvetica;}}\\f0\\fs20 " + body + "}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--commit")
    ap.add_argument("--changelog", default="")
    ap.add_argument("--metadata-only", action="store_true", help="only refresh the package description")
    a = ap.parse_args()
    c = conf()
    repo, author = c["repo"], c["author"]
    commit = a.commit or subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True,
                                        text=True, check=True).stdout.strip()
    version = header("version")
    files = packaged_files()
    tracked_and_clean(files)

    def url(path):
        return f"https://raw.githubusercontent.com/{repo}/{commit}/{quote(CATEGORY + '/' + path)}"

    if os.path.exists(INDEX):
        tree = ET.parse(INDEX)
        root = tree.getroot()
    else:
        root = ET.Element("index", version="1", name=c.get("index_name", "Larry Seyer"))
        tree = ET.ElementTree(root)
    root.set("commit", commit)
    cat = root.find(f"category[@name='{CATEGORY}']")
    if cat is None:
        cat = ET.SubElement(root, "category", name=CATEGORY)
    pkg = cat.find(f"reapack[@name='{MAIN}']")
    if pkg is None:
        pkg = ET.SubElement(cat, "reapack", name=MAIN, type="script", desc="Larry Seyer Video Effects")
    meta = pkg.find("metadata")
    if meta is None:
        meta = ET.SubElement(pkg, "metadata")
    for child in list(meta):
        meta.remove(child)
    about = ("Larry Seyer Video Effects: video effects for REAPER's Video Processor with a control panel.\n\n"
             "Color grading with wheels and curves, titles, lower thirds, tutorial callouts, zoom to region, "
             "spotlight, transitions on crossfades, picture-in-picture, borders and shadows, looks, and multicam "
             "from a multiview recording.\n\n"
             "IMPORTANT: after installing, open Actions > Show action list, search 'Larry Seyer Video Effects' and run "
             "it once. That adds the 40 LS presets to the Video Processor preset list; until then they are not there.\n\n"
             "Requires ReaImGui. Manual: " + f"https://github.com/{repo}/blob/main/{CATEGORY}/docs/MANUAL.md")
    desc = ET.SubElement(meta, "description")
    desc.text = rtf(about)
    ET.SubElement(meta, "link", rel="website").text = f"https://github.com/{repo}"
    ET.SubElement(meta, "link", rel="screenshot").text = f"https://raw.githubusercontent.com/{repo}/main/{CATEGORY}/docs/images/color_grade.jpg"
    if pkg.find(f"version[@name='{version}']") is not None:
        if a.metadata_only:
            ET.indent(tree, space="  ")
            tree.write(INDEX, encoding="utf-8", xml_declaration=True)
            print(f"index.xml: updated the package description ({version} unchanged)")
            return
        sys.exit(f"version {version} is already in index.xml: bump @version in {MAIN} (or use --metadata-only)")
    ver = ET.SubElement(pkg, "version", name=version, author=author,
                        time=datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
    if a.changelog:
        ET.SubElement(ver, "changelog").text = a.changelog
    ET.SubElement(ver, "source", main="main").text = url(MAIN)
    for act in ACTIONS:
        ET.SubElement(ver, "source", main="main", file=act).text = url(act)
    for f in files:
        ET.SubElement(ver, "source", file=f).text = url(f)
    ET.indent(tree, space="  ")
    tree.write(INDEX, encoding="utf-8", xml_declaration=True)
    print(f"index.xml: {MAIN} {version} at {commit[:10]} with {len(files) + 1 + len(ACTIONS)} files")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Shows what changed between two sets of screenshots from test/visual.

    python3 tool/visual_diff.py BEFORE_DIR AFTER_DIR OUT_DIR

For each screenshot that changed, OUT_DIR gets a PNG of the before, the
after, and their difference side by side (changed pixels in red over a
faded copy of the after). OUT_DIR/index.html shows them all, and a
Markdown summary is printed, for a CI job summary. New and removed
screenshots are listed too. Needs Pillow (pip install pillow).
"""

import html
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont

GAP = 16
LABEL = 48


def main(before_dir: Path, after_dir: Path, out_dir: Path) -> None:
    before = {p.name: p for p in before_dir.glob("*.png")} if before_dir.is_dir() else {}
    after = {p.name: p for p in after_dir.glob("*.png")}
    out_dir.mkdir(parents=True, exist_ok=True)

    changed, added, removed, same = [], [], [], []
    for name in sorted(before.keys() | after.keys()):
        if name not in before:
            added.append(name)
            Image.open(after[name]).save(out_dir / name)
            continue
        if name not in after:
            removed.append(name)
            continue
        old = Image.open(before[name]).convert("RGB")
        new = Image.open(after[name]).convert("RGB")
        if old.size == new.size and ImageChops.difference(old, new).getbbox() is None:
            same.append(name)
            continue
        share = _compose(old, new, out_dir / name)
        changed.append((name, share))

    lines = ["## Visual changes", ""]
    if not before:
        lines.append("No screenshots from the base branch to compare with.")
    elif not (changed or added or removed):
        lines.append(f"None: all {len(same)} screens look the same.")
    for name, share in changed:
        lines.append(f"- **{name}** changed ({share:.1%} of pixels)")
    lines += [f"- **{name}** is new" for name in added]
    lines += [f"- **{name}** was removed" for name in removed]
    if changed or added:
        lines += ["", "Download the `visual-changes` artifact to see them."]
    summary = "\n".join(lines) + "\n"
    print(summary)
    _write_index(out_dir, changed, added, removed)


def _compose(old: Image.Image, new: Image.Image, path: Path) -> float:
    """Saves before | after | difference to path; returns the share of
    pixels that differ."""
    width = max(old.width, new.width)
    height = max(old.height, new.height)
    old_full = Image.new("RGB", (width, height), "white")
    old_full.paste(old)
    new_full = Image.new("RGB", (width, height), "white")
    new_full.paste(new)

    mask = ImageChops.difference(old_full, new_full).convert("L").point(
        lambda v: 255 if v else 0
    )
    changed = sum(mask.histogram()[255:])
    faded = Image.blend(new_full.convert("L").convert("RGB"), Image.new("RGB", (width, height), "white"), 0.7)
    diff = Image.composite(Image.new("RGB", (width, height), (220, 0, 0)), faded, mask)

    sheet = Image.new("RGB", (3 * width + 2 * GAP, height + LABEL), "white")
    draw = ImageDraw.Draw(sheet)
    for i, (title, image) in enumerate(
        [("Before", old_full), ("After", new_full), ("Difference", diff)]
    ):
        x = i * (width + GAP)
        draw.text((x + 8, 8), title, fill="black", font=ImageFont.load_default(size=32))
        sheet.paste(image, (x, LABEL))
    sheet.save(path)
    return changed / (width * height)


def _write_index(out_dir: Path, changed, added, removed) -> None:
    parts = ["<!doctype html><meta charset=utf-8><title>Visual changes</title>",
             "<style>body{font:14px sans-serif;margin:16px}img{max-width:100%}</style>",
             "<h1>Visual changes</h1>"]
    if not (changed or added or removed):
        parts.append("<p>None.</p>")
    for name, share in changed:
        parts.append(f"<h2>{html.escape(name)}: {share:.1%} of pixels changed</h2>"
                     f"<img src='{html.escape(name)}'>")
    for name in added:
        parts.append(f"<h2>{html.escape(name)} (new)</h2><img src='{html.escape(name)}'>")
    for name in removed:
        parts.append(f"<h2>{html.escape(name)} (removed)</h2>")
    (out_dir / "index.html").write_text("\n".join(parts), encoding="utf-8")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*(Path(a) for a in sys.argv[1:]))

#!/usr/bin/env python3
"""Import Sandow SVG icons into Xcode imagesets (template PNG @1x/@2x/@3x)."""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parent.parent
ASSET_ROOT = PROJECT / "TacTech" / "Resources" / "Assets.xcassets" / "Icons"
CATALOG = ROOT / "catalog.json"
RESVG = shutil.which("resvg") or "/opt/homebrew/bin/resvg"


def pascal(stem: str) -> str:
    parts = [p for p in stem.replace("_", "-").split("-") if p]
    return "".join(p[:1].upper() + p[1:] for p in parts)


def imageset_name(style: str, stem: str) -> str:
    return f"Sandow{style.capitalize()}{pascal(stem)}"


def write_imageset(name: str, png_1x: Path, png_2x: Path, png_3x: Path) -> None:
    folder = ASSET_ROOT / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(png_1x, folder / f"{name}.png")
    shutil.copyfile(png_2x, folder / f"{name}@2x.png")
    shutil.copyfile(png_3x, folder / f"{name}@3x.png")
    (folder / "Contents.json").write_text(
        json.dumps(
            {
                "images": [
                    {"filename": f"{name}.png", "idiom": "universal", "scale": "1x"},
                    {"filename": f"{name}@2x.png", "idiom": "universal", "scale": "2x"},
                    {"filename": f"{name}@3x.png", "idiom": "universal", "scale": "3x"},
                ],
                "info": {"author": "xcode", "version": 1},
                "properties": {"template-rendering-intent": "template"},
            },
            indent=2,
        )
        + "\n"
    )


def convert_svg(svg: Path, work: Path) -> tuple[Path, Path, Path]:
    """Rasterize SVG with resvg so glyphs keep real alpha (qlmanage made white squares)."""
    work.mkdir(parents=True, exist_ok=True)
    p3 = work / "icon@3x.png"
    p2 = work / "icon@2x.png"
    p1 = work / "icon.png"
    for size, out in ((72, p3), (48, p2), (24, p1)):
        subprocess.run(
            [RESVG, "-w", str(size), "-h", str(size), str(svg), str(out)],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    return p1, p2, p3


def main() -> None:
    if not Path(RESVG).exists():
        raise SystemExit(f"resvg not found at {RESVG}. brew install resvg")

    ASSET_ROOT.mkdir(parents=True, exist_ok=True)
    catalog: list[dict] = []
    work_root = Path("/tmp/sandow-icon-import")
    if work_root.exists():
        shutil.rmtree(work_root)

    for style in ("regular", "fill"):
        svgs = sorted((ROOT / style).glob("*.svg"))
        print(f"{style}: {len(svgs)} icons")
        for index, svg in enumerate(svgs, start=1):
            name = imageset_name(style, svg.stem)
            work = work_root / style / svg.stem
            try:
                p1, p2, p3 = convert_svg(svg, work)
                write_imageset(name, p1, p2, p3)
            except Exception as error:
                print(f"FAIL {svg.name}: {error}")
                continue
            catalog.append({"style": style, "slug": svg.stem, "asset": name})
            if index % 100 == 0:
                print(f"  {style} {index}/{len(svgs)}")

    CATALOG.write_text(json.dumps(catalog, indent=2) + "\n")
    print("wrote", CATALOG, "entries", len(catalog))


if __name__ == "__main__":
    main()

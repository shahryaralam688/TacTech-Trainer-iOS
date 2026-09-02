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
    work.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["qlmanage", "-t", "-s", "72", str(svg), "-o", str(work)],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    preview = work / f"{svg.name}.png"
    if not preview.exists():
        matches = list(work.glob("*.png"))
        if not matches:
            raise FileNotFoundError(f"qlmanage produced no PNG for {svg}")
        preview = matches[0]
    p3 = work / "icon@3x.png"
    p2 = work / "icon@2x.png"
    p1 = work / "icon.png"
    shutil.copyfile(preview, p3)
    subprocess.run(["sips", "-z", "48", "48", str(p3), "--out", str(p2)], check=True, stdout=subprocess.DEVNULL)
    subprocess.run(["sips", "-z", "24", "24", str(p3), "--out", str(p1)], check=True, stdout=subprocess.DEVNULL)
    subprocess.run(["sips", "-z", "72", "72", str(p3)], check=True, stdout=subprocess.DEVNULL)
    return p1, p2, p3


def main() -> None:
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
            catalog.append(
                {
                    "style": style,
                    "slug": svg.stem,
                    "asset": name,
                }
            )
            if index % 100 == 0:
                print(f"  {style} {index}/{len(svgs)}")

    CATALOG.write_text(json.dumps(catalog, indent=2) + "\n")
    print("wrote", CATALOG, "entries", len(catalog))


if __name__ == "__main__":
    main()

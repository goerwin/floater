#!/usr/bin/env python3
"""Generate the macOS app and README icons from one SVG."""

import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
SVG_NAMESPACE = "http://www.w3.org/2000/svg"


def render(source, destination, size):
    subprocess.run([
        "rsvg-convert", "--width", str(size), "--height", str(size),
        "--output", str(destination), str(source),
    ], check=True)


def generate(source, output):
    icon = ET.parse(source).getroot()
    if icon.tag != f"{{{SVG_NAMESPACE}}}svg" or icon.get("viewBox") != "0 0 1024 1024":
        raise ValueError("The source must be a 1024 x 1024 SVG with viewBox='0 0 1024 1024'.")
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="floater-icons-") as temporary:
        iconset = Path(temporary) / "Floater.iconset"
        iconset.mkdir()
        for points in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                suffix = "@2x" if scale == 2 else ""
                render(source, iconset / f"icon_{points}x{points}{suffix}.png", points * scale)
        subprocess.run(["iconutil", "--convert", "icns", "--output", str(output / "Floater.icns"), str(iconset)], check=True)
    render(source, output / "readme-icon.png", 256)
    print(f"Generated app and README icons in {output}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT / "Resources/FloaterIcon.svg")
    parser.add_argument("--output", type=Path, default=ROOT / "Resources/Generated")
    arguments = parser.parse_args()
    if not arguments.source.is_file():
        parser.error(f"SVG source not found: {arguments.source}.")
    for tool in ("rsvg-convert", "iconutil"):
        if shutil.which(tool) is None:
            parser.error(f"Required tool not found: {tool}. Install librsvg with Homebrew for rsvg-convert.")
    try:
        generate(arguments.source.resolve(), arguments.output.resolve())
    except (ValueError, ET.ParseError, subprocess.CalledProcessError) as error:
        print(f"Asset generation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Build the bundled Google Sans Flex font files.

Google Sans Flex is distributed as a single variable font. This script
downloads the pinned upstream release, instantiates the four static styles the
app uses, and subsets them to the character coverage previously provided by
Product Sans plus general punctuation.

Outputs:
  fonts/googlesansflex_{regular,italic,bold,bold_italic}.ttf
  fonts/OFL.txt
  latchd/web-src/public/fonts/googlesansflex_*.woff2
  latchd/web-src/public/fonts/OFL.txt

Requires: fonttools (pip install fonttools)
"""

from __future__ import annotations

import hashlib
import shutil
import tempfile
import urllib.request
import zipfile
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

VERSION = "v5.000"
RELEASE_ASSET = f"GoogleSansFlex-{VERSION}.Android.zip"
RELEASE_URL = (
    "https://github.com/googlefonts/googlesans-flex/releases/download/"
    f"{VERSION}/{RELEASE_ASSET}"
)
RELEASE_SHA256 = "99412bbed27d7a774ddacd517c7eb50dee31ee2d0f53e021986eb9e86dee2d1c"
VARIABLE_FONT = "GoogleSansFlex[ROND,opsz,slnt,wdth,wght].ttf"
OFL_URL = f"https://raw.githubusercontent.com/googlefonts/googlesans-flex/{VERSION}/OFL.txt"

# Product Sans' coverage + General Punctuation and the few symbols the old
# font supplied. Keeping this list in sync avoids silently changing fallback
# behaviour for quotes, dashes, bullets, and ellipses.
UNICODES = (
    "U+0000,U+000D,U+0020-007E,U+00A0-00FF,U+0131,U+0152-0153,"
    "U+02C6,U+02DA,U+02DC,U+2000-206F,U+2074,U+20AC,U+2122,"
    "U+2190-2193,U+2212,U+2215,U+2713"
)

STYLES = {
    "regular": {"wght": 400, "slnt": 0},
    "italic": {"wght": 400, "slnt": -10},
    "bold": {"wght": 700, "slnt": 0},
    "bold_italic": {"wght": 700, "slnt": -10},
}

ROOT = Path(__file__).resolve().parent.parent
FLUTTER_FONT_DIR = ROOT / "fonts"
WEB_FONT_DIR = ROOT / "latchd" / "web-src" / "public" / "fonts"


def download(url: str, destination: Path) -> None:
    request = urllib.request.Request(url, headers={"User-Agent": "latch-font-builder"})
    with urllib.request.urlopen(request) as response, destination.open("wb") as output:
        shutil.copyfileobj(response, output)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def subset_font(source: Path, destination: Path, flavor: str | None = None) -> None:
    args = [
        str(source),
        f"--output-file={destination}",
        f"--unicodes={UNICODES}",
        "--layout-features=*",
        "--glyph-names",
        "--symbol-cmap",
        "--legacy-cmap",
        "--notdef-glyph",
        "--notdef-outline",
        "--recommended-glyphs",
        "--name-IDs=*",
        "--name-legacy",
        "--name-languages=*",
    ]
    if flavor:
        args.append(f"--flavor={flavor}")
    subset.main(args)


def verify(path: Path, weight: int, italic: bool) -> None:
    font = TTFont(path)
    assert font["OS/2"].usWeightClass == weight, path
    assert bool(font["OS/2"].fsSelection & 1) is italic, path
    assert 0x2019 in font.getBestCmap(), f"{path} is missing curly apostrophe"
    assert 0x2014 in font.getBestCmap(), f"{path} is missing em dash"
    print(f"  {path.relative_to(ROOT)}: {path.stat().st_size:,} bytes")


def main() -> None:
    FLUTTER_FONT_DIR.mkdir(parents=True, exist_ok=True)
    WEB_FONT_DIR.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="google-sans-flex-") as temp_dir:
        temp = Path(temp_dir)
        archive = temp / RELEASE_ASSET
        print(f"Downloading Google Sans Flex {VERSION}...")
        download(RELEASE_URL, archive)

        actual_hash = sha256(archive)
        if actual_hash != RELEASE_SHA256:
            raise SystemExit(
                f"Checksum mismatch for {RELEASE_ASSET}:\n"
                f"  expected {RELEASE_SHA256}\n"
                f"  actual   {actual_hash}"
            )

        with zipfile.ZipFile(archive) as bundle:
            bundle.extract(VARIABLE_FONT, temp)
        variable_font = temp / VARIABLE_FONT

        for name, coordinates in STYLES.items():
            instance_path = temp / f"instance-{name}.ttf"
            font = TTFont(variable_font)
            instance = instantiateVariableFont(
                font,
                {
                    "opsz": 18,
                    "wdth": 100,
                    "ROND": 0,
                    **coordinates,
                },
                updateFontNames=True,
            )
            instance.save(instance_path)

            ttf_path = FLUTTER_FONT_DIR / f"googlesansflex_{name}.ttf"
            subset_font(instance_path, ttf_path)

            woff2_path = WEB_FONT_DIR / f"googlesansflex_{name}.woff2"
            subset_font(instance_path, woff2_path, flavor="woff2")

            verify(ttf_path, coordinates["wght"], name.endswith("italic"))
            print(f"  {woff2_path.relative_to(ROOT)}: {woff2_path.stat().st_size:,} bytes")

    print("Downloading OFL license...")
    license_path = FLUTTER_FONT_DIR / "OFL.txt"
    download(OFL_URL, license_path)
    shutil.copyfile(license_path, WEB_FONT_DIR / "OFL.txt")
    print("Done.")


if __name__ == "__main__":
    main()

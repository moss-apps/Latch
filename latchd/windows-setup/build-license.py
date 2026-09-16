"""Build windows-setup/license.txt from the canonical legal/ texts.

The Inno Setup EULA page needs a plain .txt (it renders .rtf/.txt only),
so this concatenates the versioned sources of truth — EULA, Terms, Privacy
Policy, MIT license — into the single file latch.iss shows at install time.
Run from the repo root:  python3 latchd/windows-setup/build-license.py
The output is generated (gitignored); CI regenerates it before iscc.
"""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
LEGAL = ROOT / "legal"
OUT = pathlib.Path(__file__).resolve().parent / "license.txt"

SECTIONS = [
    ("Latch End-User License Agreement", LEGAL / "eula.md"),
    ("Latch Terms and Conditions", LEGAL / "terms.md"),
    ("Latch Privacy Policy", LEGAL / "privacy.md"),
    ("MIT License", LEGAL / "LICENSE.txt"),
]


def main() -> None:
    version = (LEGAL / "version.txt").read_text().strip()
    parts = [
        f"Latch — Legal Documents (legal version {version})",
        "This installer shows the same texts Latch Web asks you to accept",
        "on first run. Acceptance is recorded locally by latchd.",
        "",
    ]
    for title, path in SECTIONS:
        parts += [
            "=" * 72,
            title,
            "=" * 72,
            "",
            path.read_text().strip(),
            "",
            "",
        ]
    OUT.write_text("\n".join(parts).strip() + "\n")
    print(f"-> {OUT.relative_to(ROOT)} ({OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()

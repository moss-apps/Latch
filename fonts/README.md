# Google Sans Flex

Latch bundles **Google Sans Flex** for the Flutter app and the `latchd` web UI.
It replaces Product Sans, which is proprietary and cannot be redistributed.

- Upstream: https://github.com/googlefonts/googlesans-flex
- Version: `v5.000`
- License: SIL Open Font License 1.1, no Reserved Font Names (see `OFL.txt`)

The upstream release is a single variable font. The files in this directory are
static instances generated from it:

| File | Weight | Slant |
| --- | --- | --- |
| `googlesansflex_regular.ttf` | 400 | 0 |
| `googlesansflex_italic.ttf` | 400 | -10 |
| `googlesansflex_bold.ttf` | 700 | 0 |
| `googlesansflex_bold_italic.ttf` | 700 | -10 |

All instances pin `opsz 18`, `wdth 100`, and `ROND 0`. They are subset to the
same Latin and punctuation coverage the app previously used, so unsupported
scripts continue to fall back to the platform font as before.

## Regenerating

```sh
python3 scripts/build-google-sans-flex.py
```

The script downloads the pinned release, verifies its SHA-256, generates both
the Flutter TTFs here and the web WOFF2 files in
`latchd/web-src/public/fonts/`, and copies `OFL.txt` to both locations.

Requires `fonttools`:

```sh
python3 -m pip install fonttools
```

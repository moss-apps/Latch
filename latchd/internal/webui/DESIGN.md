# DESIGN.md — Latch Desktop Backup web UI

Surface: `latchd/internal/webui/web/` — a built React app (`go:embed`-served on
loopback). Source lives in `latchd/web-src/`; the built `dist/` is committed so
`make latchd` needs no Node. Rebuild with `make latchd-web`.

Mode: **Operate**. The desktop companion to one task: keep an encrypted backup
of the phone vault on this machine — pair, unlock, browse, preview, export.
The browse experience is Drive-shaped, not phone-shaped: full-width shell,
sidebar views, table/grid, viewer overlay.

The Flutter app (`lib/themes/app_colors.dart`, `lib/models/accent_color.dart`)
is the visual source of truth. When the phone app changes, this file changes
with it.

## Toolchain

Vite + React + TypeScript + Tailwind v4 + shadcn/ui (Radix primitives),
scaffolded in `web-src/`. `npm run build` → `tsc -b && vite build` into
`../internal/webui/web` (`emptyOutDir`). The dev server proxies `/api` to
`127.0.0.1:7800`. Generated shadcn components sit in `src/components/ui/`;
Latch-specific components and libs in `src/components/`, `src/lib/`.
No runtime dependency on Node — only the committed dist ships.

## World

A desktop file-browser shell, full viewport width. **h-14 app bar**: logomark +
Latch left; global search center (max 560px, `/` focuses it); lock + theme
icon-buttons right. Below, on the main view: **264px sidebar** (collapses to a
horizontal strip under md) + content area that scrolls under a sticky
content head. The content area is de-carded — flat on the page background,
hairline dividers; cards survive only where a plate genuinely helps (QR card,
viewer chrome).

Sidebar sections: **Views** (All files, Photos, Videos, Songs, Documents,
Favorites — each with a count badge, active row tinted accent@10%), **Backup**
(folder, last backup, back-up-from-phone, verify, export panel), and
**Appearance** (dark switch + 11 accent dots).

**Pairing** keeps the two-panel shape — brand, headline, numbered steps and
warning left; themed QR card right (address, chunked 64-hex code, copy chips,
live dot). Stacks under lg. **Unlock** is a minimal centered pane: lock badge,
password field, one filled button.

The logomark is the dot-matrix L (21 circles, viewBox 481×652) as a React
component, `fill: currentColor` in `--logo`. The QR is drawn client-side by
the vendored `qrcode-generator` (MIT) onto a canvas — #121212 modules on
white, quiet zone 4.

## Tokens

Two themes via the `.dark` class on `<html>` (toggled from `latchd-theme`),
accent (11 choices) overrides `--latch-accent`/`--latch-accent-variant`
inline, persisted at `latchd-accent`. Raw values live in `web-src/src/index.css`
as Latch custom properties (`--bg`, `--surface`, `--text`, …) and are mapped
into shadcn's variables (`--background`, `--card`, `--primary`, `--border`,
`--ring`, …) so every shadcn component renders Latch-colored. `@theme inline`
exposes both sets as Tailwind utilities (`bg-bg2`, `text-text2`,
`border-divider`, `bg-brand`, …). Values are copied from `app_colors.dart` /
`accent_color.dart` — do not eyeball them; re-copy on change.

| | Light | Dark |
|---|---|---|
| bg / bg2 | #FFFFFF / #F8F9FA | #1A1A1D / #242428 |
| surface / elevated | #FFFFFF / — | #2D2D32 / #38383E |
| text / 2 / 3 | #212121 / #424242 / #757575 | #E8E6E3 / #B8B6B3 / #8A8886 |
| divider / border (line) | #E0E0E0 / #BDBDBD | #3D3D42 / #4A4A50 |
| accent (blue default) | #1976D2 (var #42A5F5) | #5C9CE6 (var #7AB3F0) |
| onAccent | #FFFFFF | #1A1A1D |
| success / error | #4CAF50 / #E53935 | #66BB6A / #EF5350 |
| logo | #121212 | #F5F5F5 |

File-type colors (light/dark): image → accent; video → #D32F2F/#EF5350;
song → #9C27B0/#BA68C8; document → #EF6C00/#FFB74D; other → #757575/#8A8886;
favorite star → #FFC107 both.

## Type

ProductSans only — the repo's own `fonts/productsans_*.ttf`, self-hosted in
`public/fonts/`, referenced from `index.css`. Content title 20/700; body
14–15; meta 13 text3; table headers 11/700 uppercase. Monospace (system) for
pairing codes and the text preview only.

Icons: Flutter's own `MaterialIcons-Regular.otf`, addressed **by codepoint**
(`src/lib/glyphs.ts`, rendered by `<Mi n="…"/>`), never by ligature —
OTF ligatures proved unreliable. `lucide-react` ships with shadcn but is not
used for product UI glyphs.

## Components

- **File table** — rows on hairline dividers, hover bg2. Name cell: 32px
  thumb-or-glyph tile, truncated name, amber star. Modified (hidden under sm)
  and right-aligned size. Sortable headers with direction arrows; sorting
  also exposed as a Select in the content head. Keyboard: rows focusable,
  Enter/Space opens.
- **File grid** — `auto-fill minmax(180px,1fr)`, 4:3 media letterboxed with
  `object-contain` (portrait photos show in full, never cropped), name row
  with star. Photos defaults to grid, others to list; per-view choice
  persisted at `latchd-layout`. Layout segmented control in the content head.
- **Thumbs** — 32px (grid: full tile) lazy `<img src="/api/thumb/<id>>` with
  the type glyph behind it; on error the glyph remains. Server-generated,
  in-memory cached, never on disk. Fit is `contain` in both layouts.
- **Search** — app-bar field, debounced; overrides the sidebar view with a
  flat "Search results" context; Escape clears and returns. Rendering is
  incremental (200 rows, then a scroll sentinel) — no cap row.
- **Viewer overlay** — full-viewport, dark scrim. Header: type icon, name,
  meta (type · size · date), download (`?dl=1`), close (autofocus). Prev/next
  chevrons + ←/→/Esc navigate the filtered list. Stage by kind: image `<img>`
  with spinner, contain-fit + wheel zoom toward cursor, drag pan past 1x,
  double-click toggles fit/2.5x (max 8x), clamped inside the stage, plus an
  on-screen −/%/+ bar (% resets to fit); ctrl+wheel stays the browser's
  page zoom; video
  `<video controls autoplay playsinline>`; song glyph tile
  + `<audio controls>`; PDF `<iframe>`; text ≤2MB in `<pre>`; everything else
  a no-preview tile with download. Load errors are fetched and named (legacy
  blob → "use Export decrypted", missing blob → "pair the phone again").
- **Status lines** — leading glyph; busy = spinner, ok = success, err = error.
  Every error names the problem and the recovery, never a bare code.
- **Buttons** — shadcn Button, radius 12 defaults; filled = accent, outline =
  1px border. Loading freezes the label and overlays a spinner.
- **Fields** — filled bg2, focus border accent (mapped to shadcn Input).
- **Switch** — shadcn Switch, accent track when on.
- **Accent dots** — 36px, selected ring `inset 0 0 0 2.5px` in text color.
- **Pair card** — surface bg, radius 16; QR on a fixed white plate (scanners
  need the light ground), translucent veil while receiving/verifying/failed;
  cred rows click-to-copy; live dot pulses while pairing is active.
- **Empty states teach** — "Nothing here yet / Back up from your phone to fill
  this folder.", distinct no-matches and per-view ("No Photos in this
  backup.") variants.

## Motion

State-only, 150–250ms: switch, hover/press shifts, live-dot pulse, spinner.
No scroll reveals, no load orchestration. `prefers-reduced-motion` respected
by Tailwind's motion-safe utilities where animation is used.

## Flow

The desktop creates the credentials (spec P6.1r): `/api/pair/start` binds a
token-gated LAN receiver; the UI polls `/api/pair/status` (1.5s) through
waiting → receiving → verifying → complete, then swaps to the unlock pane.
Unlock (`/api/unlock`) keeps the master key in memory for browse/preview/
export; `/api/lock` drops it and clears search, viewer and thumbs. Verify,
export and per-file endpoints run against the unlocked session.

## Constraints

- API surface is fixed in `docs/desktop_backup.md`; the UI must not assume
  endpoints beyond it. The loopback API now includes `/api/file/<id>` and
  `/api/thumb/<id>` — both unlock-gated, documented there.
- localStorage keys `latchd-theme` / `latchd-accent` predate this rewrite and
  must stay stable; `latchd-sort` / `latchd-layout` are new.
- The committed dist in `internal/webui/web/` must always match `web-src/`;
  run `make latchd-web` after touching the UI before committing.

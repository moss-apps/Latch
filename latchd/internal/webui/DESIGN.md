---
name: Latch Desktop Backup
description: A calm local file-management companion with familiar navigation and restrained utility panels.
colors:
  bg: "#ffffff"
  bg-dark: "#1a1a1d"
  bg2: "#f8f9fa"
  bg2-dark: "#242428"
  surface: "#ffffff"
  surface-dark: "#2d2d32"
  surface-elev: "#f8f9fa"
  surface-elev-dark: "#38383e"
  text: "#212121"
  text-dark: "#e8e6e3"
  text2: "#424242"
  text2-dark: "#b8b6b3"
  text3: "#757575"
  text3-dark: "#8a8886"
  disabled: "#9e9e9e"
  disabled-dark: "#5a5856"
  divider: "#e0e0e0"
  divider-dark: "#3d3d42"
  line: "#bdbdbd"
  line-dark: "#4a4a50"
  on-accent: "#ffffff"
  on-accent-dark: "#1a1a1d"
  logo: "#121212"
  logo-dark: "#f5f5f5"
  success: "#4caf50"
  success-dark: "#66bb6a"
  error: "#e53935"
  error-dark: "#ef5350"
  ok-text: "#2e7d32"
  ok-text-dark: "#66bb6a"
  err-text: "#c62828"
  err-text-dark: "#ef5350"
  latch-accent: "#1976D2"
  latch-accent-dark: "#5C9CE6"
  latch-accent-variant: "#42A5F5"
  latch-accent-variant-dark: "#7AB3F0"
  purple: "#7B1FA2"
  purple-dark: "#AB47BC"
  purple-variant: "#9C27B0"
  purple-variant-dark: "#BA68C8"
  teal: "#00796B"
  teal-dark: "#26A69A"
  teal-variant: "#009688"
  teal-variant-dark: "#4DB6AC"
  green: "#388E3C"
  green-dark: "#66BB6A"
  green-variant: "#4CAF50"
  green-variant-dark: "#81C784"
  orange: "#E64A19"
  orange-dark: "#FF7043"
  orange-variant: "#FF5722"
  orange-variant-dark: "#FF8A65"
  pink: "#C2185B"
  pink-dark: "#EC407A"
  pink-variant: "#E91E63"
  pink-variant-dark: "#F06292"
  red: "#D32F2F"
  red-dark: "#EF5350"
  red-variant: "#F44336"
  red-variant-dark: "#E57373"
  indigo: "#303F9F"
  indigo-dark: "#5C6BC0"
  indigo-variant: "#3F51B5"
  indigo-variant-dark: "#7986CB"
  cyan: "#0097A7"
  cyan-dark: "#26C6DA"
  cyan-variant: "#00BCD4"
  cyan-variant-dark: "#4DD0E1"
  amber: "#F57C00"
  amber-dark: "#FFB74D"
  amber-variant: "#FF9800"
  amber-variant-dark: "#FFCC80"
  gunmetal: "#353E43"
  gunmetal-dark: "#353E43"
  gunmetal-variant: "#4A565C"
  gunmetal-variant-dark: "#4A565C"
  file-document: "#EF6C00"
  file-document-dark: "#FFB74D"
  favorite: "#FFC107"
typography:
  headline:
    fontFamily: '"ProductSans", "Segoe UI", system-ui, sans-serif'
    fontSize: "26px"
    fontWeight: 700
    letterSpacing: "-0.025em"
  title:
    fontFamily: '"ProductSans", "Segoe UI", system-ui, sans-serif'
    fontSize: "20px"
    fontWeight: 700
    letterSpacing: "-0.025em"
  section-title:
    fontFamily: '"ProductSans", "Segoe UI", system-ui, sans-serif'
    fontSize: "18px"
    fontWeight: 700
    lineHeight: "28px"
  body:
    fontFamily: '"ProductSans", "Segoe UI", system-ui, sans-serif'
    fontSize: "14px"
    fontWeight: 400
    lineHeight: "20px"
  label:
    fontFamily: '"ProductSans", "Segoe UI", system-ui, sans-serif'
    fontSize: "14px"
    fontWeight: 700
    lineHeight: "20px"
  meta:
    fontFamily: '"ProductSans", "Segoe UI", system-ui, sans-serif'
    fontSize: "13px"
  caption:
    fontFamily: '"ProductSans", "Segoe UI", system-ui, sans-serif'
    fontSize: "12px"
    lineHeight: "16px"
  table-label:
    fontFamily: '"ProductSans", "Segoe UI", system-ui, sans-serif'
    fontSize: "11px"
    fontWeight: 700
    letterSpacing: "0.07em"
  code:
    fontFamily: '"JetBrains Mono", "Cascadia Code", ui-monospace, monospace'
    fontSize: "13px"
rounded:
  sm: "7.2px"
  md: "9.6px"
  lg: "12px"
  xl: "16.8px"
  pane: "16px"
  browser-control: "10px"
  full: "9999px"
spacing:
  "2": "8px"
  "3": "12px"
  "4": "16px"
  "5": "20px"
  "6": "24px"
  "8": "32px"
  "10": "40px"
components:
  button-primary:
    backgroundColor: "{colors.latch-accent}"
    textColor: "{colors.on-accent}"
    rounded: "{rounded.lg}"
    height: "44px"
    padding: "0 16px"
  button-outline:
    backgroundColor: "{colors.bg}"
    textColor: "{colors.text}"
    rounded: "{rounded.lg}"
    height: "44px"
    padding: "0 16px"
  button-ghost:
    rounded: "{rounded.lg}"
    height: "44px"
    padding: "0 12px"
  input-export:
    textColor: "{colors.text}"
    rounded: "{rounded.lg}"
    height: "44px"
    padding: "4px 10px"
  navigation-row:
    textColor: "{colors.text2}"
    rounded: "{rounded.lg}"
    padding: "0 16px"
  utility-panel:
    backgroundColor: "{colors.bg2}"
    textColor: "{colors.text}"
    rounded: "{rounded.lg}"
    padding: "{spacing.4}"
  accent-choice:
    rounded: "{rounded.full}"
    size: "28px"
  settings-switch:
    rounded: "{rounded.full}"
    width: "32px"
    height: "18.4px"
---

# Design System: Latch Desktop Backup

## Overview

**Creative North Star: "A coherent, calm local file-management app"**

Latch uses familiar Google Drive navigation and Proton's restrained utility-panel treatment with Latch's own logo, palette, ProductSans, and Material icons. The world is flat, real application UI: files, settings, and phone backup are useful destinations, with task titles and controls in the first viewport rather than an oversized brand presentation. There are no physical decorative materials in this approved direction.

The redesign boundary is the shared shell, full-page settings, phone pairing, and responsive browser layout. The incumbent table/grid browser and viewer remain the functional reference. Settings uses grouped rows; pairing places a scannable QR beside phone instructions with manual and USB disclosures. These are expressions of the confirmed direction, not composition requirements for every future screen.

**Key Characteristics:**
- Familiar destination navigation with retained file-view state.
- Flat tonal surfaces, hairline dividers, and restrained utility panels.
- Latch identity with saved light/dark and accent preferences.
- Readable task titles, controls, credentials, and recovery states.

This is an approved merge of the incumbent design record with the current implementation. Evidence is `latchd/web-src/src/index.css`, `src/lib/theme.ts`, `src/components/{Sidebar,SettingsView,PairingView,MainView,BrowserPane}.tsx`, `src/App.tsx`, and the shared `src/components/ui/` primitives. Root `PRODUCT.md` supplies the durable local-only product context; `docs/desktop_backup.md` owns protocol details.

Source is `latchd/web-src/` (Vite, React, TypeScript, Tailwind v4, shadcn/Radix); the embedded artifact is `latchd/internal/webui/web/`. The incumbent delivery convention commits the built output so the desktop binary needs no Node runtime. Application changes use `make latchd-web` to refresh that output. This documentation refresh changes neither source nor embedded assets.

## Colors

Latch's existing accent sits against neutral light/dark surfaces; status and file-kind colors keep their established meanings. Frontmatter records source values, with `-dark` counterparts documenting the `.dark` theme. Component frontmatter records the light/default role assignment; rendered components must use the live CSS variables so theme and saved accent choices apply.

### Primary

- **Ocean Blue** (`latch-accent`, `latch-accent-variant`): default primary actions, selected navigation tint, checked switches, and focus rings. `theme.ts` replaces `--latch-accent` and `--latch-accent-variant` inline before first paint.
- **Saved accent choices:** Ocean Blue, Royal Purple, Emerald Teal, Forest Green, Sunset Orange, Rose Pink, Ruby Red, Deep Indigo, Sky Cyan, Golden Amber, and Gunmetal Gray. Their light/dark base and variant values come directly from `ACCENTS`, mirrored from `lib/models/accent_color.dart`; the choices are alternatives to the primary, not simultaneous secondary palettes.

### Neutral

- **Page and shell** (`bg`, `bg2`): content panes use the page ground; header and navigation use the secondary ground.
- **Surface layers** (`surface`, `surface-elev`): existing surface vocabulary, including neutral hover and elevated contexts. The light elevated surface is the secondary ground, not an undefined value.
- **Text hierarchy** (`text`, `text2`, `text3`, `disabled`): foreground, explanations, metadata, and disabled content. Settings explanations use `text2`; the export input explicitly uses foreground text.
- **Separators** (`divider`, `line`): hairline content divisions and stronger input strokes respectively.
- **Identity and on-accent** (`logo`, `on-accent`): logo follows the theme; filled primary controls use the established contrasting text role.

### Semantic colors

- **Feedback** (`success`, `error`, `ok-text`, `err-text`): status marks and readable success/error text. The text-specific green and red differ from the light indicator colors.
- **File kinds:** image follows the selected accent; video uses the red light/dark pair; song uses the purple variant pair; document uses `file-document`; other uses `text3`. Favorites use `favorite` in both themes.

**The Live Latch Palette Rule.** Use the existing CSS roles and saved accent choices; derive identity values from Latch's source tokens rather than estimating replacement colors.

Raw custom properties in `index.css` map to shadcn roles: `--background` → `--bg`, `--foreground` → `--text`, `--primary`/`--ring` → `--latch-accent`, `--primary-foreground` → `--on-accent`, `--border` → `--divider`, and `--input` → `--line`. Theme persistence stays at `latchd-theme` and `latchd-accent`.

## Typography

**Body and heading font:** ProductSans with Segoe UI, system-ui, and sans-serif fallbacks. The regular, italic, bold, and bold-italic faces are self-hosted from `public/fonts/`; no replacement font is introduced.

**Code font:** the existing mono stack in frontmatter, used for pairing credentials, USB commands, and text previews. The stylesheet names JetBrains Mono and Cascadia Code as fallbacks; it does not self-host those fonts.

### Hierarchy

- **Headline:** settings and phone-backup page titles, bold with tight tracking.
- **Title:** file-browser context title, bold with tight tracking.
- **Section title:** settings group headings; pairing subheadings use a smaller bold body-sized step (16px).
- **Body / label:** compact explanations and navigation; setting-row labels are bold. Longer explanations use relaxed line height (1.625), while ordinary body text uses the frontmatter body role.
- **Meta / caption:** file-grid names and code use the small step; timestamps, counts, legal navigation context, and network notes use compact supporting text.
- **Table label:** bold, uppercase with the incumbent spaced tracking. This is a table convention, not a requirement to uppercase ordinary labels.

There is no display/hero type role in the scoped surfaces. The observed ramp is task-oriented, not a geometric marketing scale. Setting descriptions cap at 48ch; pairing introduction and network note cap at 65ch and 75ch respectively.

Product glyphs retain Flutter's `MaterialIcons-Regular.otf`, addressed by codepoint through `src/lib/glyphs.ts` and `<Mi>`, not ligatures. The Latch logomark remains the 21-circle dot-matrix L (`viewBox="0 0 481 652"`), filled with `currentColor` through `--logo`.

**The Task Title Rule.** Lead utility pages with their task title and useful controls; keep the Latch mark at shared-shell scale.

## Layout

### Shared shell and responsive navigation

- The shell fills the dynamic viewport height. The header has a minimum height (64px), a secondary ground, and a bottom divider. Its Latch mark is compact (28px high) beside the wordmark; header icon-button targets are 44px square.
- At `md` (768px), the navigation is a persistent sidebar (232px) with All files, Photos, Videos, Songs, Documents, and Favorites, followed by Phone backup and Settings. Counts appear only when unlocked and positive. Backup controls and appearance controls live in Settings, not inside this sidebar.
- Below `md`, the sidebar is replaced by a modal left drawer, not a horizontal navigation strip. Drawer width is `min(300px, calc(100vw - 40px))`; it has its own close control, scrim, and focus return to the menu trigger.
- Content panes scroll independently. At `md` and above, each pane has right/bottom inset (16px) and rounded outer corners (`pane`); mobile panes use the available width without that inset.
- Search is visible only for unlocked files. Its desktop wrapper caps at 720px, including horizontal padding; mobile search occupies a second full-width header row. Lock is also files-only; theme toggle remains shared.

### Settings

Settings is a full destination pane with a centered maximum width (1040px). Utility-page padding is 20px horizontal / 24px vertical at the base, 32px both ways at `sm` (640px), and 40px horizontal at `lg` (1024px). Legal-document reading uses a narrower maximum width (860px).

Groups are Backup & export, Appearance, and Legal. Setting rows are flat grids with bottom dividers, vertical padding (20px), and a single stacked column below `sm`. At `sm`, they become two equal minmax columns, label/explanation left and control/value right, with a wider gap (32px). Groups have bottom separation (36px). Switch wrappers have minimum height (48px), horizontal padding (12px), and right-align from `sm`.

### Pairing

Phone backup shares the utility-page width and padding. A back action and task title precede Receive backup / Restore to phone tabs. Below `lg`, the session content stacks QR first, then phone steps and disclosures. At `lg`, it becomes a two-column grid: QR/status/actions left (280px), phone steps and disclosures right (`minmax(0, 1fr)`), separated by 32px. The QR plate is 232px square around a 200px canvas, centered when stacked and left-aligned on desktop.

The manual/USB details remain in the phone-instructions column. The trusted-network note and cancel action form a shared footer below both columns. This supersedes the old QR-right, branded-left two-panel account.

### Incumbent file browser

The file-browser context header remains sticky and wraps controls. File grids retain `repeat(auto-fill, minmax(180px, 1fr))`, with a 14px gap and 4:3 media. The table hides Modified below `sm`, retains right-aligned Size, and uses 32px thumbnail/glyph tiles. Photos defaults to grid; other views default to list. `latchd-layout` retains per-view layout, and `latchd-sort` retains sorting.

**The Destination Continuity Rule.** Moving between files, settings, and phone backup preserves file-view selection and mounted operation state; navigation closes the viewer, and returning to pairing adopts the current session.

## Elevation & Depth

The scoped shell and utility pages are flat at rest: tonal grounds, pane silhouettes, borders, and dividers carry hierarchy. Settings does not turn each row into a card. A neutral panel appears for a concrete USB approval request; the QR retains a white scanning plate. No physical decorative surface is part of this world.

Overlay depth is functional. The mobile drawer has a black 40% scrim and sits above the shell; the incumbent viewer uses `rgba(12,12,14,0.86)` over the full viewport. The file-browser sticky header retains a 95% page ground with backdrop blur, and viewer zoom controls retain their translucent backdrop. Those existing treatments do not establish a general glass-panel style.

Focus is also functional depth: shared buttons/inputs/switches use an accent ring (3px, 50% ring color) and accent border; global button, summary, and link focus adds a foreground outline (2px, 3px offset). File-grid focus uses a narrower accent ring. These are state treatments, not ambient shadows.

Motion is state-driven: ordinary shared transitions use the Tailwind default (150ms); the mobile drawer enters with a 220ms clip reveal and `cubic-bezier(0.16, 1, 0.3, 1)`. Busy indicators spin or pulse; pairing's dot pulses while transferring, not simply while waiting. The global reduced-motion rule shortens animations/transitions to 0.01ms and limits animation iterations to one. There is no scroll-reveal choreography in these surfaces.

**The Flat Utility Rule.** Use tonal grounds and row dividers for routine settings; reserve a separate panel for a concrete grouped interaction such as USB approval.

## Shapes

The frontmatter's `sm` / `md` / `lg` / `xl` radii are the stylesheet's existing multiples of `--radius` (0.75rem), resolved at the normal root size. Shared controls and navigation use `lg`; file-grid and QR corners also use that radius. The desktop outer pane uses the distinct `pane` radius. Compact browser controls retain their incumbent `browser-control` radius. These are established variants, not interchangeable rounded-card defaults.

Circles are functional: status dots, numbered phone steps, accent choices, and switch tracks/thumbs. Accent swatches are 28px circles inside 44px radio-label targets, with a small white/dark check marker for selection. Pairing credentials use softly rounded secondary-ground blocks and wrap instead of truncating.

## Components

### Buttons

Restrained, recognizable actions. The primary variant uses live accent/on-accent roles; outline uses the page ground and divider stroke, with a stronger input stroke and translucent input ground in dark mode; ghost gains a neutral hover ground. All retain the shared `lg` shape, medium small text, focus ring, disabled opacity (50%), and one-pixel press translation for non-popup actions.

Settings and pairing generally override the primitive's 32px default height to 44px; their primary/outline actions commonly use 16px horizontal padding and copy/ghost actions 12px. Primary hover reduces accent opacity to 80%. The implementation has secondary, destructive, and link library variants; this scoped record's previews focus on the primary, outline, and ghost variants actually used here. Verify/export change labels to “Verifying…” / “Exporting…”; a frozen label plus overlaid spinner is not their current pattern.

### Inputs / Fields

The shared input has an input-role stroke, `lg` corners, transparent light ground, and a 30% input-role ground in dark mode. Focus changes the border to accent and adds the shared ring; invalid states use destructive border/ring; disabled states tint the ground and reduce opacity. It is not universally filled with `bg2`.

The export field is 44px high, has a visible label, and explicitly uses `--foreground` text so the value stays readable in either theme. It sits beside an outline Export button, with a wrapping destination path and operation result below. The app-bar search is a separate filled secondary-ground field, 40px high, with page-ground/line-stroke focus treatment.

### Navigation

Rows have a 44px minimum height, 16px horizontal padding, Material glyph, label, and optional count. Inactive text uses `text2`; hover uses `surface`; current-page state uses accent at 10%, bold foreground text, and `aria-current="page"`. The same destination list is used in the desktop sidebar and modal mobile drawer.

### Settings rows, switches, and accent choices

Rows pair a bold label and optional explanation with a control or value. Backup & export contains the local path/date, phone-backup action, verification, and local decrypted export; locked-state guidance links back to unlock. Appearance contains dark mode, image thumbnails, and the eleven accent radios. Legal links open documents inside the settings pane, with a back action.

Switches retain the small visible track (32px × 18.4px), accent when checked and input-role when unchecked. The settings-specific pseudo-element extends horizontally by 12px and vertically by 14px: its touch area is approximately 56px × 46.4px (46px high rounded), contained in a 48px-minimum-height wrapper with horizontal padding. Do not mistake the visible track for the hit target. Accent choices use native radio semantics, focus outlines, visible selected checks, and the current accent name above the swatches.

### Pairing tabs, QR, and connection disclosures

The tabs use a foreground underline and bold selected label, not filled pills. They support arrow/Home/End navigation and disable restore before a local backup exists; mode changes are disabled during transfer. Session states name preparation, waiting, receiving/sending, verifying, completion, expiry, cancellation, and errors with recovery instructions.

The client-side QR keeps dark modules on fixed white, a four-module quiet zone, and the existing generator. An opaque neutral state overlay replaces the active QR while preparing, transferring/verifying, closed, or unable to render; manual connection remains available when QR rendering fails. A textual live status accompanies the dot.

Phone steps use small numbered circles. Native `details`/`summary` disclosures expose manual address/code and USB instructions, with a 48px minimum summary target and a rotating chevron. Addresses and commands break anywhere; chunked pairing codes wrap and are selectable. Separate outline copy buttons provide “Copied” or manual-copy feedback; credential blocks are not click-to-copy rows. USB permission is a concrete neutral panel with Allow once / Deny. The existing plain-HTTP/trusted-network note stays visible in the footer.

### File table, grid, search, and viewer

- **Table:** flat hairline-divided rows, secondary-ground hover/focus, truncated names, optional favorite star, sortable headers and a sort selector. Focusable rows open with Enter/Space.
- **Grid:** bordered rounded tiles with contain-fit 4:3 media and compact name/star rows. Thumbnails are lazy, retain a type-glyph fallback, and can be disabled through the existing appearance preference. Images remain contain-fit in both layouts.
- **Search:** deferred filename filtering takes precedence over the selected file category and changes context to “Search results.” `/` focuses search on unlocked files. Escape in the current search input blurs it; it does not clear the query or restore the category. Clearing the query restores the selected view. Rendering remains incremental in 200-item chunks with a scroll sentinel.
- **Viewer:** full-viewport dark overlay with filename, type/size/date, download, autofocus close, and previous/next navigation through the filtered list using arrows/Escape. Images support contain-fit, cursor-centered wheel zoom, clamped pan above 1×, double-click fit/2.5×, an 8× maximum, and an on-screen zoom/reset bar. Ctrl/Meta-wheel retains browser zoom. Video/audio use native controls; PDF uses an iframe; text preview caps at 2MB; other formats offer download. Legacy-file and missing-blob errors retain the incumbent export/re-pair recovery guidance.
- **Empty states:** distinguish an empty backup (“Back up from your phone to fill this folder.”), no filename matches, and an empty category. Unlock remains the incumbent centered password pane.

Protocol, receiver lifecycle, and thumbnail storage behavior belong to `docs/desktop_backup.md` and their implementation, rather than being new visual-system guarantees. The desktop credential creation and unlocked browse/preview/export model remain incumbent product behavior.

## Do's and Don'ts

### Do:
- **Do** retain Latch's logo, ProductSans, codepoint Material icons, and saved light/dark and accent choices.
- **Do** use live CSS variables for themed controls, including explicit foreground text in the export input.
- **Do** keep files, settings, and phone backup as shared-shell destinations with retained file-view and operation state.
- **Do** stack settings controls and pairing content on narrow screens, use the mobile drawer, and allow full credentials to wrap.
- **Do** preserve contain-fit file imagery, sorting, per-view layouts, incremental rendering, and viewer behavior.
- **Do** retain visible keyboard focus, the enlarged settings-switch touch area, and textual status/recovery alongside indicators.

### Don't:
- **Don't** replace the confirmed Latch assets or estimate new brand colors.
- **Don't** introduce physical decorative materials or oversized logo presentations into the approved utility surfaces.
- **Don't** move settings controls back into the navigation sidebar or make Settings a dialog.
- **Don't** carry forward the obsolete horizontal mobile navigation, QR-right pairing layout, or click-to-copy credential-row account.
- **Don't** crop file previews or truncate pairing credentials to fit the redesigned shell.

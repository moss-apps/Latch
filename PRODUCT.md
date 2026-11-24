# Latch

Latch is a local file vault with opt-in encryption: a Flutter phone app and a
small Go desktop backup companion. The companion keeps a snapshot of the phone
vault on your own computer. It can receive a backup, restore one to the phone,
unlock it, browse and preview files, verify it, and export readable copies.
There are no accounts and no cloud storage in that flow.

## Desktop companion

The browser UI runs on localhost. A token-gated receiver on the LAN opens only
while a pairing session is active. Files transfer as stored, so hidden-only
files stay unencrypted. The manifest and wrapped key bundle are encrypted, but
plain HTTP does not encrypt transport. Say that plainly before a transfer and
use a trusted LAN or USB, not a public network.

The desktop UI has a shared shell, full-page settings, and phone pairing that
works at browser widths. Settings is a sidebar destination, not a dialog. The
navigation will feel familiar to anyone who has used Google Drive; the utility
panels are restrained, in the spirit of Proton Drive. Keep Latch's logo, Google
Sans Flex, Material icons, light/dark themes, and saved accent choices, and
keep the existing file browser.

The goal is simple: people should find preferences and backup actions quickly,
connect a phone with a QR code or manual/USB instructions, and understand what
is happening during connection, transfer, completion, expiry, and failure.
Navigation should keep the current file view and any in-progress operation.
Narrow layouts still need touch targets, keyboard focus, and pairing
credentials that can be read in full.

Source: `latchd/web-src/`. Embedded output: `latchd/internal/webui/web/`.
Visual reference: `latchd/internal/webui/DESIGN.md`. Protocol:
`docs/desktop_backup.md`.

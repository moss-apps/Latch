# Latch

Latch is a local encrypted file vault with a Flutter phone app and a Go desktop
backup companion. The companion keeps a snapshot of the phone vault on the
user's own computer. It supports receiving a backup, restoring to a phone,
unlocking, browsing, previewing, verifying, and exporting readable files locally.
There are no accounts or cloud storage in this flow.

## Desktop companion brief

The browser interface is served on localhost. A token-gated LAN receiver opens
only for a pairing session. Transfers carry encrypted files over plain HTTP;
the interface must explain that users should pair on trusted networks.

The approved redesign covers the shared shell, full-page settings, and phone
pairing, including responsive browser layouts. Settings is a sidebar destination,
not a dialog. Use familiar Google Drive navigation and restrained Proton Drive
control/panel treatment while retaining Latch's logo, ProductSans, Material icons,
light/dark themes, and saved accent choices. Preserve the existing file browser.

Success means users can find preferences and backup operations quickly, connect
their phone with a QR code or manual/USB instructions, and understand connection,
transfer, completion, expiry, and error states. Navigation must preserve file-view
selection and in-progress operation results. Narrow layouts must support touch,
keyboard focus, and fully readable pairing credentials.

Implementation source: `latchd/web-src/`. Embedded output:
`latchd/internal/webui/web/`. Visual reference:
`latchd/internal/webui/DESIGN.md`. Protocol: `docs/desktop_backup.md`.

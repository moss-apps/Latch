#!/bin/sh
# Latch desktop companion installer — fetches latchd from GitHub Releases
# so users can host Latch Web without cloning the repo.
#
# Usage:
#	curl -fsSL https://raw.githubusercontent.com/moss-apps/Latch/HEAD/scripts/install-latchd.sh | sh
#
# Overrides: LATCHD_REPO, LATCHD_VERSION (an app-version tag, e.g. 0.18.0-beta.1), LATCHD_BINDIR.
set -eu

REPO="${LATCHD_REPO:-moss-apps/Latch}"
BINDIR="${LATCHD_BINDIR:-$HOME/.local/bin}"
VERSION="${LATCHD_VERSION:-}"

fail() { echo "install-latchd: $*" >&2; exit 1; }

os=$(uname -s)
case "$os" in
	Linux) os=linux ;;
	*) fail "unsupported OS '$os'. This installer covers Linux; on Windows download latchd-windows-amd64.exe from https://github.com/$REPO/releases" ;;
esac

arch=$(uname -m)
case "$arch" in
	x86_64) arch=amd64 ;;
	aarch64 | arm64) arch=arm64 ;;
	*) fail "unsupported architecture '$arch'" ;;
esac

command -v curl >/dev/null 2>&1 || fail "curl is required"

if [ -z "$VERSION" ]; then
	# Release tags carry the mobile version (0.x.y-beta.z); old prefixed
	# tags (Latch-*, v*, latchd-*) start with a letter and never match.
	# grep -o keeps document order regardless of compact/pretty JSON.
	VERSION=$(curl -fsSL "https://api.github.com/repos/$REPO/releases?per_page=100" |
		grep -o '"tag_name": *"[^"]*"' |
		sed -n 's/^"tag_name": *"\([0-9][^"]*\)"$/\1/p' |
		head -n 1)
fi
[ -n "$VERSION" ] || fail "no release found in $REPO (looked for 0.* version tags)"

asset="latchd-$os-$arch"
base="https://github.com/$REPO/releases/download/$VERSION"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo ">> downloading $asset from $VERSION"
curl -fsSL -o "$tmp/$asset" "$base/$asset"
curl -fsSL -o "$tmp/SHA256SUMS" "$base/SHA256SUMS"

# Verify when sha256sum exists; minimal distros may lack it.
if command -v sha256sum >/dev/null 2>&1; then
	want=$(grep " $asset\$" "$tmp/SHA256SUMS" || true)
	[ -n "$want" ] || fail "no checksum entry for $asset in SHA256SUMS"
	got=$(sha256sum "$tmp/$asset" | cut -d' ' -f1)
	[ "$got" = "${want%% *}" ] || fail "checksum mismatch for $asset"
	echo ">> checksum ok"
else
	echo "!! sha256sum not found; skipping verification" >&2
fi

mkdir -p "$BINDIR"
chmod +x "$tmp/$asset"
mv "$tmp/$asset" "$BINDIR/latchd"

# The binary must at least run on this machine.
"$BINDIR/latchd" --version >/dev/null 2>&1 ||
	fail "installed binary failed to run; wrong architecture?"

DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"

# App icon: the Latch dot-L on a rounded blue tile.
mkdir -p "$DATA_DIR/icons/hicolor/scalable/apps"
cat >"$DATA_DIR/icons/hicolor/scalable/apps/latchd.svg" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="-60 -60 601 772">
  <rect x="-60" y="-60" width="601" height="772" rx="110" fill="#1976d2"/>
  <g fill="#ffffff">
    <circle cx="31.36" cy="318.03" r="31.36"/><circle cx="31.36" cy="422.57" r="31.36"/><circle cx="31.36" cy="527.1" r="31.36"/><circle cx="31.36" cy="620.34" r="31.36"/>
    <circle cx="80.88" cy="120.26" r="31.36"/><circle cx="80.88" cy="224.8" r="31.36"/>
    <circle cx="135.6" cy="31.36" r="31.36"/><circle cx="135.6" cy="318.03" r="31.36"/><circle cx="135.6" cy="620.34" r="31.36"/>
    <circle cx="241.15" cy="31.36" r="31.36"/><circle cx="240.14" cy="318.03" r="31.36"/><circle cx="240.14" cy="620.34" r="31.36"/>
    <circle cx="345.4" cy="31.36" r="31.36"/><circle cx="344.68" cy="318.03" r="31.36"/><circle cx="344.68" cy="620.34" r="31.36"/>
    <circle cx="397.52" cy="120.26" r="31.36"/><circle cx="397.52" cy="224.8" r="31.36"/>
    <circle cx="449.64" cy="318.03" r="31.36"/><circle cx="449.64" cy="422.57" r="31.36"/><circle cx="449.64" cy="527.1" r="31.36"/><circle cx="449.64" cy="620.34" r="31.36"/>
  </g>
</svg>
EOF

# Application menu entry; no-arg latchd serves and opens the browser.
mkdir -p "$DATA_DIR/applications"
cat >"$DATA_DIR/applications/latchd.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Latch Web
GenericName=Desktop Backup
Comment=Host Latch Web for the Latch mobile app
Exec="$BINDIR/latchd"
Terminal=false
Icon=latchd
Categories=Utility;FileTools;
Keywords=latch;backup;vault;
StartupNotify=true
EOF
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$DATA_DIR/applications" 2>/dev/null || true

# Optional systemd user service (installed but not enabled).
mkdir -p "$CONFIG_DIR/systemd/user"
cat >"$CONFIG_DIR/systemd/user/latchd.service" <<EOF
[Unit]
Description=Latch Web (desktop backup companion)
After=network.target

[Service]
ExecStart=$BINDIR/latchd serve --addr 127.0.0.1:7800
Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target
EOF

case ":$PATH:" in
	*":$BINDIR:"*) ;;
	*) echo ">> note: $BINDIR is not in your PATH" ;;
esac

echo ">> installed $BINDIR/latchd ($VERSION)"
echo ">> installed app menu entry (Latch Web), icon and systemd unit"
echo
echo "Start it:     latchd   (or launch Latch Web from your app menu)"
echo "Web UI:       http://127.0.0.1:7800"
echo "Always on:    systemctl --user enable --now latchd"
echo "On the phone: Latch > Settings > Storage > Desktop Backup > scan the QR"

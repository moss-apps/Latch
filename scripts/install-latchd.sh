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

case ":$PATH:" in
	*":$BINDIR:"*) ;;
	*) echo ">> note: $BINDIR is not in your PATH" ;;
esac

echo ">> installed $BINDIR/latchd"
echo
echo "Start it:    latchd serve"
echo "Then open:   http://127.0.0.1:7800"
echo "On the phone: Latch > Settings > Storage > Desktop Backup > scan the QR"

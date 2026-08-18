#!/bin/bash
# Build, package into the .app bundle, sign, and restart the daemon.
#
# Why the bundle and the signing identity both matter:
#
# 1. The daemon must run from inside a signed .app bundle. TCC will not honour
#    an Accessibility grant for a bare Mach-O binary, and without Accessibility
#    CGEvent.post() no-ops, so every key: action dies with nothing logged.
#
# 2. It must be signed with a real identity, not ad-hoc. An ad-hoc signature's
#    designated requirement is a bare cdhash, so every rebuild is a new identity
#    and silently voids the Accessibility grant. Signing with a certificate
#    makes the requirement:
#        identifier "com.streamdeck.controller" and certificate leaf = H"..."
#    which is independent of the binary's contents and survives rebuilds.
#
# Set up the signing identity once with a self-signed code-signing certificate
# (see SIGNING_IDENTITY below). If it is missing this script stops rather than
# falling back to ad-hoc, because the fallback would appear to work and then
# break key: actions until the grant was re-added by hand.
set -euo pipefail

cd "$(dirname "$0")"
APP="$HOME/Applications/StreamDeckController.app"
AGENT="$HOME/Library/LaunchAgents/com.streamdeck.controller.plist"
SIGNING_IDENTITY="StreamDeckController Local Signing"

if ! security find-identity -v -p codesigning | grep -q "$SIGNING_IDENTITY"; then
    echo "error: signing identity '$SIGNING_IDENTITY' not found or not trusted." >&2
    echo "Check with: security find-identity -v -p codesigning" >&2
    exit 1
fi

swift build -c release

launchctl bootout "gui/$(id -u)" "$AGENT" 2>/dev/null || true

mkdir -p "$APP/Contents/MacOS"
cp .build/release/StreamDeckController "$APP/Contents/MacOS/StreamDeckController"
codesign --force --sign "$SIGNING_IDENTITY" "$APP"

launchctl bootstrap "gui/$(id -u)" "$AGENT"

echo
echo "Deployed to $APP"
codesign -d -r- "$APP" 2>&1 | grep designated
echo "Log: ~/Library/Logs/StreamDeckController.log"

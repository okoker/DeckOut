#!/bin/bash
# Checks an assembled DeckOut bundle (T-107): plists, names, signatures, architecture, nothing loose in the root.
# Usage: scripts/check-bundle.sh "build/DeckOut Dev.app"
set -euo pipefail
app="${1:?usage: check-bundle.sh <path to DeckOut.app>}"
fail() { echo "FAIL ($app): $*" >&2; exit 1; }
pb() { /usr/libexec/PlistBuddy -c "Print :$1" "$2" 2>/dev/null || true; }

[ -d "$app/Contents" ] || fail "no Contents folder"
info="$app/Contents/Info.plist"
plutil -lint -s "$info" || fail "Info.plist missing or doesn't lint"
id=$(pb CFBundleIdentifier "$info")
case "$id" in
    io.github.okoker.deckout|io.github.okoker.deckout.dev) ;;
    *) fail "unexpected bundle id '$id'" ;;
esac
[ "$(pb CFBundleExecutable "$info")" = "DeckOut" ] || fail "CFBundleExecutable isn't DeckOut"
[ "$(pb LSMinimumSystemVersion "$info")" = "15.0" ] || fail "LSMinimumSystemVersion isn't 15.0"
[ -n "$(pb CFBundleVersion "$info")" ] || fail "no CFBundleVersion"

label="$id.agent"
plist="$app/Contents/Library/LaunchAgents/$label.plist"
plutil -lint -s "$plist" || fail "agent plist $label.plist missing or doesn't lint"
[ "$(pb Label "$plist")" = "$label" ] || fail "agent Label isn't $label"
[ "$(pb "MachServices:$label" "$plist")" = "true" ] || fail "agent doesn't own Mach service $label"
[ "$(pb BundleProgram "$plist")" = "Contents/MacOS/DeckOutAgent" ] || fail "BundleProgram isn't the helper"
[ "$(pb ProgramArguments:1 "$plist")" = "--mach-service" ] || fail "ProgramArguments lacks --mach-service"
[ "$(pb ProgramArguments:2 "$plist")" = "$label" ] || fail "--mach-service doesn't name $label"
[ "$(pb KeepAlive "$plist")" = "true" ] || fail "KeepAlive isn't true"

for exe in DeckOut DeckOutAgent; do
    [ -x "$app/Contents/MacOS/$exe" ] || fail "no executable $exe"
    [ "$(lipo -archs "$app/Contents/MacOS/$exe")" = "arm64" ] || fail "$exe isn't arm64 only"
done
helper_id=$(codesign -dv "$app/Contents/MacOS/DeckOutAgent" 2>&1 | sed -n 's/^Identifier=//p')
[ "$helper_id" = "$label" ] || fail "helper signed as '$helper_id', not $label"
app_id=$(codesign -dv "$app" 2>&1 | sed -n 's/^Identifier=//p')
[ "$app_id" = "$id" ] || fail "app signed as '$app_id', not $id"
codesign --verify --strict "$app" || fail "signature doesn't verify"
m1ddc="$app/Contents/Helpers/m1ddc"
[ -x "$m1ddc" ] || fail "no Contents/Helpers/m1ddc"
[ "$(lipo -archs "$m1ddc")" = "arm64" ] || fail "m1ddc isn't arm64 only"
[ "$(codesign -dv "$m1ddc" 2>&1 | sed -n 's/^Identifier=//p')" = "$id.m1ddc" ] || fail "m1ddc not signed as $id.m1ddc"
for res in Phosphor-Bold.ttf Phosphor-Fill.ttf phosphor-icons.json Phosphor-LICENSE.txt; do
    [ -f "$app/Contents/Resources/$res" ] || fail "missing resource $res"
done
extra=$(ls -A "$app" | grep -vx Contents || true)
[ -z "$extra" ] || fail "loose files in the bundle root: $extra"
echo "OK: $app ($id, build $(pb CFBundleVersion "$info"))"

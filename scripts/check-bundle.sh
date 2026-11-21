#!/bin/bash
# Checks an assembled DeckOut bundle (T-107): plists, names, signatures, architecture, nothing loose in the root.
# With --signed (T-193), also that the release app is ready to ship: Developer ID, one team, hardened runtime, secure
# timestamp, exactly the Apple Events entitlement. It never prints the certificate's name (the Authority= lines).
# Usage: scripts/check-bundle.sh [--signed] "build/DeckOut Dev.app"
set -euo pipefail
signed=0
if [ "${1:-}" = --signed ]; then signed=1; shift; fi
app="${1:?usage: check-bundle.sh [--signed] <path to DeckOut.app>}"
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
[ -n "$(pb NSAppleEventsUsageDescription "$info")" ] || fail "no NSAppleEventsUsageDescription"

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
for res in Phosphor-Bold.ttf Phosphor-Fill.ttf phosphor-icons.json Phosphor-LICENSE.txt DeckOut-LICENSE.txt m1ddc-LICENSE.txt; do
    [ -f "$app/Contents/Resources/$res" ] || fail "missing resource $res"
done
# The debug runs' switches are compiled in only under DEBUG (BL-024). The release app must not carry
# --show-old-controller, which sits in the same DEBUG block as --selftest and --snapshot. Only that name is checked: an
# optimised build keeps strings of up to 15 bytes inside the machine code, where grep never sees them.
if [ "$id" = io.github.okoker.deckout ]; then
    ! grep -a -q -- --show-old-controller "$app/Contents/MacOS/DeckOut" \
        || fail "the release app carries the debug switches (--show-old-controller found)"
fi
extra=$(ls -A "$app" | grep -vx Contents || true)
[ -z "$extra" ] || fail "loose files in the bundle root: $extra"

if [ "$signed" = 1 ]; then
    [ "$id" = io.github.okoker.deckout ] || fail "--signed checks the release app only, not $id"
    want='{"com.apple.security.automation.apple-events":true}'
    team=""
    for code in "$app" "$app/Contents/MacOS/DeckOutAgent" "$m1ddc"; do
        name=$(basename "$code")
        sig=$(codesign -dvv "$code" 2>&1 | grep -v '^Authority=')
        ! grep -q '^Signature=adhoc' <<<"$sig" || fail "not signed with a Developer ID (ad hoc): $name"
        t=$(sed -n 's/^TeamIdentifier=//p' <<<"$sig")
        [ -n "$t" ] && [ "$t" != "not set" ] || fail "no TeamIdentifier: $name"
        [ -z "$team" ] || [ "$t" = "$team" ] || fail "signed by a different team from DeckOut.app: $name"
        team=$t
        grep -q '^CodeDirectory .*flags=0x[0-9a-f]*([^)]*runtime' <<<"$sig" || fail "no hardened runtime: $name"
        grep -q '^Timestamp=' <<<"$sig" || fail "no secure timestamp: $name"
        ents=$(codesign -d --entitlements - --xml "$code" 2>/dev/null || true)
        if [ "$code" = "$m1ddc" ]; then
            [ -z "$ents" ] || fail "m1ddc carries entitlements"
        else
            got=$(plutil -convert json -o - - <<<"$ents" 2>/dev/null || true)
            [ "$got" = "$want" ] || fail "entitlements aren't exactly the Apple Events one: $name"
        fi
    done
    codesign --verify --deep --strict "$app" || fail "signature doesn't verify (deep, strict)"
fi
echo "OK: $app ($id, build $(pb CFBundleVersion "$info")$([ "$signed" = 1 ] && echo ", Developer ID signed"))"

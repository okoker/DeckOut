# Progress

## Current Status
v2 daemon running as launchd service. All buttons, knobs, LCD icons, system volume, and ZR7 volume working.
Last run 02/11/2026: manual device test (no automated suite) — brightness knob cycles All → Left → Right → All, Right adjusts only the right screen; no daemon crash reports after the test.

## Active Work
_(None)_

## Completed
- Phase 1: Core daemon — HID device, CRT protocol, event parsing, action dispatch
- Phase 2: LCD key icons via BAT protocol (85x85, auto-trim transparency, calibrated viewport offset)
- ZR7Player volume/mute via DistributedNotifications (com.zr7.volumeUp/Down/muteToggle)
- SIGHUP config hot-reload (new action mappings + LCD icons without restart)
- launchd daemon installed: ~/Library/Application Support/StreamDeckController/, ~/.config/vsd/config.json
- Volume control via NSEvent media key simulation (shows HUD)
- Bug fixes: sendPacket report ID stripping, configKey mapping, CFRunLoop requirement
- Brightness knob fixes (02/11/2026): mode cycle stuck on Left — `refreshDisplays()` reset the mode to All on every press (regression from the 02/04/2026 hot-plug refresh); daemon crash ~2.5 s after the HUD closed — NSWindow over-release, fixed with `isReleasedWhenClosed = false`

## Completed Phases
_(Completed phases move to `old_progress/XX_phase_name.md`)_

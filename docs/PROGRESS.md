# Progress

## Current Status
v2 daemon running as launchd service. All buttons, knobs, LCD icons, system volume, ZR7 volume, and monitor brightness working.
Last run 02/11/2026: manual device test (no automated suite) — brightness knob cycles All → Left → Right → All, Right adjusts only the right screen; no daemon crash reports after the test.

## Active Work
_(None)_

## Completed
- launchd daemon installed (27/03/2026): ~/Library/Application Support/StreamDeckController/, ~/.config/vsd/config.json
- Volume control via CoreAudio `kAudioDevicePropertyVolumeScalar` (27/03/2026) — replaced NSEvent media keys, which need Accessibility and break on every reinstall
- Bug fixes (27/03/2026): sendPacket report ID stripping, configKey mapping, CFRunLoop requirement
- Brightness knob fixes (02/11/2026): mode cycle stuck on Left — `refreshDisplays()` reset the mode to All on every press (regression from the 02/04/2026 hot-plug refresh); daemon crash ~2.5 s after the HUD closed — NSWindow over-release, fixed with `isReleasedWhenClosed = false`

## History
- 01 — Core build (27/03/2026): core daemon, LCD icons, ZR7 volume, SIGHUP reload → `old_progress/01_core_build.md`

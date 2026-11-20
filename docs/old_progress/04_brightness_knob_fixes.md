# 04 — Brightness knob fixes (02/11/2026)

Moved out of `PROGRESS.md` on 20/11/2026.

- Brightness knob fixes (02/11/2026): mode cycle stuck on Left — `refreshDisplays()` reset the mode to All on every press (regression from the 02/04/2026 hot-plug refresh); daemon crash ~2.5 s after the HUD closed — NSWindow over-release, fixed with `isReleasedWhenClosed = false`. Checked by hand 02/11/2026: the knob cycles All → Left → Right → All, Right adjusts only the right screen; no crash reports after the test.

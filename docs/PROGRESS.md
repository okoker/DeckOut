# Progress

## Current Status
One launchd daemon drives the TreasLin N3 and the MiraBox N4 (installed 19/11/2026 from `feat/n4-support`): buttons,
knobs, LCD icons, the N4's live strip and lock photo, system volume, ZR7 volume and monitor brightness all working.
Last run 19/11/2026: `swift test` 59/59 (T-001–T-059, T-059 new in Task 11), watched; device checks on both decks
(every control, reload, live strip, lock, both decks together, two 10-min performance windows), then a key on each
deck, the internet tile and a lock / unlock on the installed daemon.

## Active Work
- N4 support: whole-branch review, then merge on the owner's word (`docs/TODO.md`).

## Completed

### 19/11/2026 — The N4 works next to the N3: its own layout, a live strip, a photo while locked
- **Reference:** `docs/reference/n4.md`; design `docs/design/n4_support.md` (✅ built); KI-009.
- **For a person:** plug in either deck or both; each shows its own icons and runs its own actions. The N4's strip
  shows internet latency, CPU / memory and volume, live; locking the Mac puts a photo across the N4 and makes keys
  inert while the volume knob still works. Reloading the config redraws without a blink.
- **Decision (owner, 19/11/2026):** N4 layout — knob 1 free, 2 monitor brightness, 3 ZR7, 4 system volume; bottom
  row Tailscale, iTerm, Homelab Topology, Notes (first key empty); strip internet / load / empty / volume; deck
  brightness 75. The network popup runs `networkDetail2.sh` in a login shell (`zsh -lc`) so Homebrew tools are found
  — also on the N3. The N4 goes on USB-A (KI-009). Lock-photo framing and brightness wait for the config app.
- **Checked:** the owner worked every control on both decks with the log open; lock, sleep-to-lock and unlock; unplug
  each deck while the other runs. Lock-photo positions measured from two photos of a test grid. Performance:
  0.135 % of one core with both decks and the live strip, 0.015 % with the N3 alone (old daemon 0.008 %, a 7-day
  average — owner told); memory 19 MB vs 17 MB. The Mac never system-slept (display sleep only), so a real sleep's
  USB power loss is covered only by the unplug checks.

- Volume control via CoreAudio `kAudioDevicePropertyVolumeScalar` (27/03/2026) — replaced NSEvent media keys, which need Accessibility and break on every reinstall
- Bug fixes (27/03/2026): sendPacket report ID stripping, configKey mapping, CFRunLoop requirement
- Brightness knob fixes (02/11/2026): mode cycle stuck on Left — `refreshDisplays()` reset the mode to All on every press (regression from the 02/04/2026 hot-plug refresh); daemon crash ~2.5 s after the HUD closed — NSWindow over-release, fixed with `isReleasedWhenClosed = false`. Checked by hand 02/11/2026: the knob cycles All → Left → Right → All, Right adjusts only the right screen; no crash reports after the test.

## History
Older work: `old_progress/README.md`.

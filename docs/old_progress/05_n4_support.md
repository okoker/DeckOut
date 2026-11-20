# 05 — N4 support (19/11/2026)

Moved out of `PROGRESS.md` on 20/11/2026.

### 19/11/2026 — The N4 works next to the N3: its own layout, a live strip, a photo while locked
- **Reference:** `docs/reference/n4.md`; design `docs/design/n4_support.md` (✅ built); KI-009.
- **For a person:** plug in either deck or both; each shows its own icons and runs its own actions. The N4's strip
  shows internet latency, CPU / memory and volume, live; locking the Mac puts a photo across the N4 and makes keys
  inert while the volume knob still works. Reloading the config redraws without a blink.
- **Decision (owner, 19/11/2026):** the owner's own N4 layout in the live config, strip internet / load / empty /
  volume, deck brightness 75. A shell action that needs Homebrew tools runs in a login shell (`zsh -lc`). The N4
  goes on USB-A (KI-009). Lock-photo framing and brightness settings wait for the config app.
- **Checked:** the owner worked every control on both decks with the log open; lock, sleep-to-lock and unlock; unplug
  each deck while the other runs. Lock-photo positions measured from two photos of a test grid. Performance:
  0.135 % of one core with both decks and the live strip, 0.015 % with the N3 alone (old daemon 0.008 %, a 7-day
  average — owner told); memory 19 MB vs 17 MB. The Mac never system-slept (display sleep only), so a real sleep's
  USB power loss is covered only by the unplug checks.

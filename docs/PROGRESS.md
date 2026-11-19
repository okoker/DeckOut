# Progress

## Session Handover — 19/11/2026 (late night, owner away)

**Autonomous run to UAT** (owner, 19/11/2026): build DeckOut through phase 6 while the owner is away, then UAT.
Standing go for live test sessions (stop the installed daemon → register the dev agent on a copy of the config →
test → unregister → start the installed daemon again and check it). Commits on local branches, not pushed or merged
until UAT. No signing. Downloads allowed: m1ddc source, Phosphor icons. Plans and ledgers:
`docs/superpowers/plans/2026-11-19-deckout-{2,3}-*.md`, `.superpowers/sdd/<plan>/progress.md`.

### Where it stands
- Plan 2 (the app shell) built on `deckout-2-app-shell`: 127 tests, two test sessions, fresh review fixed (I1, I2);
  minors are BL-006–BL-010. Plan 3 (editing) is drafted and next, on `deckout-3-editing`.
- The installed daemon is the plan 1 build, running; the dev app is `~/Applications/DeckOut Dev.app`, unregistered.

### Recorded only here (still open)
- Plan 1 review minors: M1 `script:`/`shortcut:` killed at 30 s like `shell:` (owner's call); M2 `ConfigFile.save`
  doesn't parse-check what it writes (plan 3 Task 1); M3 `showLockPhoto` isn't merged and re-reads the photo per call
  (plan 4's drag); M6 `--show-lock-photo` ignores reloads; M8 each reload logs the whole config (plan 3 Task 2); M10
  `NSXPCListener(machServiceName:)` with a name the job doesn't own may crash-loop under KeepAlive (unverified; the
  plist and the argument come from one Makefile variable); M11 unverified: a `.zshrc` touching Documents / Desktop /
  iCloud prompts in the daemon's name.
- Older: `Daemon` / `DeckManager` have no teardown (only matters if the app ever embeds a `Daemon`; it doesn't); the
  volume tile shows "0%" on outputs with no volume control; knob inputs skip the lock recheck (≤5 s window); a deck
  reconnecting at the lock screen shows its layout ≤5 s before the photo; an unplug mid-redraw logs up to 15 warnings.
- Signing: before the first signed build the owner checks which authority issued the Developer ID certificate. Not
  urgent: only builds after 01/02/2027 would need a G2 certificate, and the team id (what the checks use) stays.

## Current Status
One launchd daemon drives the TreasLin N3 and the MiraBox N4 (DeckOut plan 1 build, installed 19/11/2026). The DeckOut
app shell (plan 2) is built on a local branch: it registers its agent, checks signatures both ways, and shows the
plugged-in deck as it is, live strip included; editing comes with plan 3.
19/11/2026 — DeckOut plan 1 on `deckout-1-background`: `swift test` 95/95 (new T-061–T-094); device session with the owner: volume ±5, app/url/open/Shortcut keys, play/pause (QuickTime), preset switch, framed lock photo, blank start without config; log: shell environment resolved (arp-scan via /opt/homebrew/bin), 10 SIGHUPs → 1 reload (75 ms). Not met: reload under 50 ms; next/previous track unverified.
19/11/2026 — DeckOut plan 2 on `deckout-2-app-shell`: `swift test` 127/127 (new T-095–T-118), watched; `scripts/check-bundle.sh` on both variants; two test sessions on this Mac without the owner (registration, foreign client refused, update restart, both decks drawn in the real window via `--snapshot`); plug / unplug and key presses not checked (owner, at UAT).

## Active Work
- DeckOut plan 3, editing (`docs/superpowers/plans/2026-11-19-deckout-3-editing.md`), then plans 4–6, then UAT.
  Backlog: BL-002–BL-010.

## Completed

### 19/11/2026 — DeckOut is an app: it runs the deck controller and shows your deck as it is
- **Reference:** `docs/reference/app.md` (new); design `docs/design/config_app.md` (phase 2); plan
  `docs/superpowers/plans/2026-11-19-deckout-2-app-shell.md`; T-095–T-118; KI-008 (rewritten); BL-006–BL-010.
- **For a person:** DeckOut.app holds the deck controller, renamed DeckOutAgent, and starts it at login through
  macOS's Login Items; no Terminal. Open the app and it shows the deck that's plugged in, drawn as it looks, with the
  live strip moving; both plugged in, it asks which; none, it asks you to plug one in. It says when it's in the wrong
  folder, switched off in Login Items, or can't reach the controller. Only DeckOut's own app can talk to the
  controller. Nothing is editable yet (plan 3).
- **Decision (owner, 19/11/2026):** build through phase 6 unattended, with test sessions on this Mac and local
  commits; UAT at the end. (CL calls, in the plan:) ad hoc builds pin the app's exact binary; the app restarts an
  agent of another build once; the dev variant has its own config and logs and installs to `~/Applications`.
- **Checked:** `swift test` 127/127; two test sessions on this Mac (run line above). Session 2 found KI-008 again
  with the new agent: a replaced, unregistered agent was killed on its first start and launchd lost the job; the
  app now unregisters and registers it afresh when it doesn't answer. A fresh reviewer found two important issues
  (a refused agent never reported; a vanished one still shown as running), both fixed test-first.

### 19/11/2026 — The daemon is ready for the DeckOut app: presets, photo framing, new actions, no reload stall
- **Reference:** design `docs/design/config_app.md` (phases 0–1; plan 1 built); `docs/REQUIREMENTS.md` (Configuration,
  Actions, Daemon Behaviour); `docs/reference/n4.md`; `docs/reference/device_quirks.md` (media keys); T-061–T-094.
- **For a person:** a reload no longer freezes the decks while the monitors are read, and a burst of saves redraws
  once. Each deck can hold several layouts (presets), one of them live. Keys can open an app, a website, a file or
  folder, run a script or one of Apple's Shortcuts, or play / pause / skip; volume and monitor keys take a step. The
  lock photo can be zoomed and moved. Commands find Homebrew tools (your own shell's PATH). With no usable config the
  daemon runs with blank decks and says why, instead of crash-looping. All set by hand in the JSON until the app exists.
- **Decision (owner, 19/11/2026):** built natively on a branch, merged and pushed to GitHub (no release tag), then
  installed as the daemon. The rename to DeckOut waits for plan 2. A reload's full redraw (75–158 ms) stays for now
  as BL-005. The XPC service takes any caller running as the owner until plan 2's signing check; nothing starts it yet.
- **Checked:** `swift test` 95/95; a fresh reviewer's three important findings fixed test-first. Device session with
  the owner (run line in Current Status): every new action kind, presets, the framed lock photo, a blank start, the
  layout kept when the file went missing. Next / previous track unverified (no track player here); the owner's
  network script needs a terminal, so `script:` can't run it.

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

- Brightness knob fixes (02/11/2026): mode cycle stuck on Left — `refreshDisplays()` reset the mode to All on every press (regression from the 02/04/2026 hot-plug refresh); daemon crash ~2.5 s after the HUD closed — NSWindow over-release, fixed with `isReleasedWhenClosed = false`. Checked by hand 02/11/2026: the knob cycles All → Left → Right → All, Right adjusts only the right screen; no crash reports after the test.

## History
Older work: `old_progress/README.md`.

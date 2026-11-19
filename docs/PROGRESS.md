# Progress

## Session Handover — 19/11/2026 (night)

**Next session: write DeckOut plan 2, the app shell** (superpowers:writing-plans), from `docs/design/config_app.md`
phase 2 and "After this plan" in `docs/superpowers/plans/2026-11-19-deckout-1-background.md`. Before relying on
`SMAppService`, read Karabiner-Elements and Copilot for Xcode at source (both cited in the design).

### What was done
- Plan 1 built on `deckout-1-background` (`323a6ff`…`f219806`), fast-forward merged, branch deleted, **pushed** (GitHub
  main = `f219806`, the 22 N4 commits too; no release tag); device session done (run line below). Its release build is
  **installed** as the daemon (22:24, PID 33804): log clean, both decks, monitors ready in 344 ms off the main thread.

### Uncommitted state
- `docs/BACKLOG.md` BL-005; `docs/TODO.md` line now points at plan 2; `docs/PROGRESS.md` this handover + the plan 1
  run line. The owner hasn't said whether to commit them. `.DS_Store` is the owner's — leave it.

### Decisions made (not yet in docs)
- Plan 2 sets the XPC code-signing requirement before any agent plist passes `--mach-service`, dev builds included:
  until then `test` lets any process running as the owner use `key:` / media with the daemon's Accessibility grant.
- Plan 1 review minors, recorded only here: M1 `script:`/`shortcut:` killed at 30 s like `shell:` (owner's call);
  M2 `ConfigFile.save` doesn't parse-check what it writes (plan 3 needs it); M3 `showLockPhoto` isn't merged and
  re-reads the photo per call (plan 4's drag); M6 `--show-lock-photo` ignores reloads; M8 each reload logs the whole
  config (log growth under app saves); M9 `Agent.version` is read lazily, so read it at launch for plan 2's version
  check; M10 unverified: `NSXPCListener(machServiceName:)` with a name the job doesn't own may crash-loop under
  KeepAlive; M11 unverified: a `.zshrc` touching Documents / Desktop / iCloud prompts in the daemon's name.
- Older findings, still recorded only here: `Daemon` / `DeckManager` have no teardown (IOKit callbacks hold an
  unretained pointer), needed before the app embeds a `Daemon`; the volume tile shows "0%" on outputs with no volume
  control; knob inputs skip the lock recheck (≤5 s window); a deck reconnecting at the lock screen shows its layout
  ≤5 s before the photo; an unplug mid-redraw logs up to 15 warnings.

### Environment state
- Rollback in `~/Library/Application Support/StreamDeckController/`: `.n4` (N4 build), `.prev` (v1.0.0, pairs with
  `config.json.prev`). Live config unchanged (loads as preset "Default"). Test Shortcut "Show Notification" can go.

### What's next
1. Write plan 2 in a fresh session, then build it natively as plan 1 was.
2. Owner, before plan 2's first signed build: check in Keychain Access which authority issued the Developer ID
   certificate (the original Sub-CA can't sign after 01/02/2027: make one from G2). Every signing act needs a go.
3. Open with the owner: commit the uncommitted docs; a PROGRESS "Completed" entry for plan 1; a release or not;
   a key press on each deck to confirm the install.

## Current Status
One launchd daemon drives the TreasLin N3 and the MiraBox N4 (DeckOut plan 1 build, pushed and installed 19/11/2026):
buttons, knobs, LCD icons, the N4's live strip and lock photo, system volume, ZR7 volume and monitor brightness all
working; presets, lock-photo framing and the new action kinds are in, set by hand until the config app exists.
Last run 19/11/2026: `swift test` 60/60 (T-001–T-060; T-059 new in Task 11, T-060 from the final review), watched; device checks on both decks
(every control, reload, live strip, lock, both decks together, two 10-min performance windows), then a key on each
deck, the internet tile and a lock / unlock on the installed daemon.
19/11/2026 — DeckOut plan 1 on `deckout-1-background`: `swift test` 95/95 (new T-061–T-094); device session with the owner: volume ±5, app/url/open/Shortcut keys, play/pause (QuickTime), preset switch, framed lock photo, blank start without config; log: shell environment resolved (arp-scan via /opt/homebrew/bin), 10 SIGHUPs → 1 reload (75 ms). Not met: reload under 50 ms; next/previous track unverified.

## Active Work
- None. Next: DeckOut plan 2, the app shell (`docs/TODO.md`). Backlog: BL-002–BL-005.

## Completed

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

- Volume control via CoreAudio `kAudioDevicePropertyVolumeScalar` (27/03/2026) — replaced NSEvent media keys, which need Accessibility and break on every reinstall
- Bug fixes (27/03/2026): sendPacket report ID stripping, configKey mapping, CFRunLoop requirement
- Brightness knob fixes (02/11/2026): mode cycle stuck on Left — `refreshDisplays()` reset the mode to All on every press (regression from the 02/04/2026 hot-plug refresh); daemon crash ~2.5 s after the HUD closed — NSWindow over-release, fixed with `isReleasedWhenClosed = false`. Checked by hand 02/11/2026: the knob cycles All → Left → Right → All, Right adjusts only the right screen; no crash reports after the test.

## History
Older work: `old_progress/README.md`.

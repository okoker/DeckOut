# Progress

## Session Handover — 20/11/2026: BL-003 done, everything on `main`; next: finish UAT and release (phase 7)

### What was done
- ae9ee09 BL-003: DeckOut's m1ddc is patched (reads wait 50 ms, are checked, asked again; `Vendor/m1ddc/README.md`);
  the agent reads each monitor on the first turn and never moves one from a guess; the HUD fits and centres its
  text. The owner turned the knob on the decks: it works.
- 95eecc1: `deckout-7-uat-fixes` (plans 2–7, backlog fixes, BL-003) fast-forwarded into `main` and pushed; every
  `deckout-*` branch deleted (owner). Work happens on `main` now.
- Upstream: waydabber/m1ddc#81 (from the fork okoker/m1ddc) offers the same patch. If it merges, vendor upstream
  again and drop ours.

### Uncommitted state
- This handover only. `.DS_Store` and `_user_private/` stay untracked.

### Environment state
- The decks run on DeckOut Dev (`~/Applications`, debug build 261121.012023 of `main`; agent
  `io.github.okoker.deckout.dev.agent`; config `~/.config/vsd-dev/config.json`; log `~/Library/Logs/DeckOut Dev/agent.log`).
  The hand install is retired (`~/Library/LaunchAgents/com.streamdeck.controller.plist.retired-by-deckout`); rollback:
  DeckOut Dev → Settings → Stop and Remove, `mv` the plist back, `launchctl bootstrap gui/$(id -u) <plist>`.
- After `make install-dev`, opening the app restarts the agent on the new build. KI-008 can refuse it: if the window
  stays on "not running", quit DeckOut Dev and open it again (Try Again right away doesn't help).
- After every install, Accessibility (keyboard shortcuts, media keys, commands that send keystrokes) needs the
  "DeckOut Dev" entry removed and the app added again: the old entry stays on but no longer matches the new build.

### Release gotchas (phase 7)
- The signed DeckOut is a different app from DeckOut Dev: its own bundle id, agent and config folder (`~/.config/vsd`,
  not `vsd-dev`). The UAT edits live in `vsd-dev/config.json`, and its generated icons point into
  `~/.config/vsd-dev/icons/`: carry config and icons over (owner's go), and Stop and Remove DeckOut Dev first (two
  agents fire every press twice). The signed agent needs Accessibility granted again.
- **Must not be skipped (owner, 20/11/2026):** the move copies the icons and lock photos into `~/.config/vsd/` and
  rewrites every path in the carried config to point there; none may still point into `~/.config/vsd-dev/`. Each
  app removes unused icon files from its own folder at start-up (BL-018 / BL-023), judging "used" by its own config
  only: run DeckOut Dev again after an edit there, and it deletes icons the signed app's config still points at, and
  those keys go black. Check: `grep -c vsd-dev ~/.config/vsd/config.json` is 0.
- Nothing for signing exists yet: no Makefile target, no gitignored identity file (design: Constraints; Signing during
  development). Before the first signed build the owner checks who issued the certificate (only builds after
  01/02/2027 need a G2 one). Every `codesign` / `notarytool` run needs the owner's go; never pick the identity.
- Untested: KI-008 under a Developer ID signature; launchd taking the agent plist from a quarantined download on
  macOS 27 (design: Testing). Fresh-install tests need a macOS VM tool: ask before installing one.
- Docs at release: README rewrite (it still describes the hand install; its permissions section is wrong: shortcuts,
  media keys and keystroke-sending commands need Accessibility for the app, not Input Monitoring), the design's "✅ BUILT" marker, a pointer
  from the ideas note. VERSION says 2.0.0.

### Still open, recorded only here
- Plan 1 review minors: M1 `script:`/`shortcut:` killed at 30 s like `shell:` (owner's call); M6 `--show-lock-photo`
  ignores reloads; M10 unverified: `NSXPCListener(machServiceName:)` with a name the job doesn't own may crash-loop
  under KeepAlive; M11 unverified: a `.zshrc` touching Documents / Desktop / iCloud prompts in the agent's name.
- Older: the volume tile shows "0%" on outputs with no volume control; knob inputs skip the lock recheck (≤5 s
  window); a deck reconnecting at the lock screen shows its layout ≤5 s before the photo; an unplug mid-redraw logs
  up to 15 warnings.

### What's next
1. UAT is done (owner, 20/11/2026), but for removal: Stop and Remove of DeckOut Dev, the first step of moving the
   decks to the signed app in phase 7, is its test. Swiping the strip to change presets is done (BL-033).
2. Write the phase 7 plan (`docs/superpowers/plans/`): signing target + identity file, release build, notarise, the
   GitHub release, README rewrite, moving the owner's decks to the signed app, fresh-install test in a VM, and an
   update test of the signed build (KI-008: install build 1, then build 2, open the app once: the agent must start
   the first time; if not, build the 15 s recovery). Each
   signing, notarising, publishing and install act gets its own go.
3. Then BL-029 (live strip blocks people add), designed first.

## Current Status
DeckOut Dev (`~/Applications`, a debug build of `main`) drives the TreasLin N3 and the MiraBox N4
through its own agent; the hand install is retired. The app (design phases 2–6, plus the UAT fixes) has passed the
owner's UAT (removal is tested in phase 7): it runs the deck controller from its bundle, edits every control,
presets, brightness, the lock photo, generated icons, monitors and its own removal.
21/11/2026 — BL-033 on `main` (3582782, 5e479ff, then the `0x38` fix): `swift test` 241/241 (new T-189–T-192), watched; T-191 failed with the hand-off moved above the lock check. `make install-dev` (build 261121.000629); the owner's N4 swipe set to `next_preset` by hand (backup `~/.config/vsd-dev/config.json.bak-2026-11-21`); the agent restarted on it without KI-008. Owner's swipes: 18 switched, 26 came as `0x38` and were ignored; timed round: every swipe and gap tap `0x38`. Fix: T-005 failed first (`0x38` decoded to nothing), 241/241 after; build 261121.012023: 9 of 9 swipes switched. Owner, later: a locked Mac ignores swipes (four "ignored while locked" in the log); swiping steps through the presets. Not checked: the app's preset menu following a swipe.
20/11/2026 — Pushed d215e87..ffc7631 (BL-031, BL-022, BL-015, BL-007, BL-018 + BL-023); `make install-dev` (build 261120.165253) after backing up `~/.config/vsd-dev` to `~/.config/vsd-dev.bak-2026-11-20`; one `--snapshot` run: "removed 31 unused icon files", exactly the 31 a separate grep over the backup predicted (4 named by the config kept, `config.json` unchanged, nothing else touched); KI-008 on the restart, registered again; the agent drew 14 of 14 and 6 of 6 with no warnings; window "Deck controller running", the N3's six icons drawn. Not checked yet: the clicks for BL-031, BL-022, BL-015, BL-007 (owner).
20/11/2026 — BL-018 + BL-023 on `main`: `swift test` 237/237 (new T-186–T-188), watched; T-186 and T-188 failed first against do-nothing stubs; with the code in, each of six guards taken out in turn failed a test (config check, unreadable file, links, subfolders, undo history, once per run), sources restored byte for byte. Not installed; not checked: the start-up log line and the icons folder after a real launch (owner). Phase 7 must rewrite `vsd-dev` paths (Release gotchas).
20/11/2026 — BL-007 on `main`: `swift test` 234/234 (new T-185), watched; T-185 failed first (the N3's JPEG of a 2:1 icon filled 72 × 73, the square), and again with the old drawing put back after the fix. Square icons draw as before (a square fitted in a square is the same square). Not installed; not checked: a non-square icon on the real N3 (owner).
20/11/2026 — BL-015 on `main`: `swift test` 233/233 (new T-183, T-184), watched; both failed first (Undo / Redo always on, the first Allow… watch still running after a second click). Scratch probe (not in the repo): macOS posts begin-editing at a field's first keystroke, none on focus alone, end-editing on leaving. BL-019 and BL-015's slider pause → KI-012 (owner). Not installed; not checked: the greyed menu items and ⌘Z on typing in the real app (owner).
20/11/2026 — BL-022 on `main`: `swift test` 231/231 (new T-181, T-182), watched; T-181 failed first (choosing Library wrote a star tile at once), T-182 failed first (Bold picked nothing); T-181's popover check failed with the fix's `choosingSymbol` line removed (a check on the segment's selection didn't, and was replaced). Not installed; not checked: Library, Bold / Fill and closing the popover in the real window (owner).
20/11/2026 — BL-031 on `main`: `swift test` 229/229 (new T-179, T-180), watched; T-179 failed first (⌘Z in a sheet undid the deck change behind it, ⇧⌘Z redid it), T-180 failed first with the window's state moved to the model but still hung on the editor (no window while no editor showed). BL-008 → KI-011 (owner). Not installed; not checked: ⌘Z in the real command window and a preset sheet, New Preset… still opening (owner).
20/11/2026 — BL-016 and BL-025 on `main`: `swift test` 227/227 (new T-178), watched; T-178 failed first (2 loads of an unreadable preview photo per draw, after moving the choice into `LockPhoto.slicesToDraw` unchanged); BL-025 changes no behaviour (same search, one copy). Not installed.
20/11/2026 — BL-017 on `main`: `swift test` 226/226 (new T-177; T-136 unchanged), watched; T-177 failed first (a replaced photo was decoded 1 time of 3). Not installed; not checked: a replaced photo in the real photo mode (owner).
20/11/2026 — BL-012 on `main`: `swift test` 225/225 (new T-176; T-131 follows the new answer: nil when done), watched; T-176 failed first (it didn't build: nothing said why). Installed with BL-014's list part (build 261120.135333): the agent restarted on it and drew 14 of 14 and 6 of 6; the `--snapshot` run quit early (not crashed), not rerun. Not checked: the message on screen, a new Shortcut in the picker (owner).
20/11/2026 — BL-014 (Shortcut list part) on `main`: `swift test` 224/224 (new T-175), watched; T-175 failed first (the list came back the same after DeckOut came to the front and after a second picker). Not installed yet; not checked: a Shortcut made in the Shortcuts app showing up in the real picker (owner).
20/11/2026 — BL-024 on `main`: `make app VARIANT=release` failed first at the new bundle check ("the release app carries the debug switches (--show-old-controller found)"), passes after (0 in the release binary, 1 in the dev one); `make app` (dev) OK; `swift test` 222/222, watched. Not installed: the debug build behaves as before.
20/11/2026 — UAT fixes on `main` (toolbar, About licences): `swift test` 222/222 (new T-174), watched; T-174 failed first (a licence line measured 506 pt for 464); `make install-dev` (build 261120.132255), one `--snapshot` run: "toolbar menu off, display mode 2, window 540 pt high" (540 before too), the toolbar items' middles on the window buttons' row (25.5 pt; 19.5–21 under Icon and Text), KI-008 on the restart, registered again, drew 14 of 14 and 6 of 6. Owner: licences read well; not checked: the owner's look at the Icon Only toolbar.
20/11/2026 — BL-003 on `deckout-7-uat-fixes` (ae9ee09): `swift test` 221/221 (new T-170–T-173), watched; T-170, T-171, T-173 failed first against the old code (a 0 read at start-up became 5 %, a failed read 55 %, the message measured 940 pt for 660); m1ddc on both LG monitors, 100 back-to-back reads each: stock 87 of 200 wrong (exit 0), patched 0 wrong, 0 failed; `make install-dev` (build 261120.111028), one `--snapshot` run: KI-008 on the restart, registered again, window "Deck controller running", the agent found both monitors without reading them ("Monitors ready in 31 ms", was 311–520) and drew 14 of 14 and 6 of 6. Not checked: a knob turn and the HUD on screen (owner).
20/11/2026 — BL-005 on `deckout-7-uat-fixes` (to 38094e3): `swift test` 217/217 (new T-169), watched; `make install-dev` (build 261120.103217), one `--snapshot` run: KI-008 on the restart, the app re-registered 10 s later, window "Deck controller running"; the agent drew 6 of 6 and 14 of 14 on connect; one `--post-reload` with nothing changed: "Drew 0 of 6 slots on n3 in 1 ms", "Drew 0 of 14 slots on n4 in 4 ms", "Reloaded in 7 ms" (433–453 ms before). Not checked: a changed key and an unlock on the decks (owner, at UAT).
20/11/2026 — Seven backlog fixes on `deckout-7-uat-fixes` (to 1b615ac): `swift test` 210/210 (new T-162–T-168), watched; `make install-dev` (build 261120.035630), then one `--snapshot` run of the real app: it asked the old agent to restart, the new one hit KI-008 and the app's own recovery re-registered it 10 s later; the window said "Deck controller running" (the new agent's build), and the agent drew the N3 and the N4's lock photo (Mac locked). Not checked: live strip pushes (paused while locked), every click (owner, at UAT).
19/11/2026 — DeckOut plan 1 on `deckout-1-background`: `swift test` 95/95 (new T-061–T-094); device session with the owner: volume ±5, app/url/open/Shortcut keys, play/pause (QuickTime), preset switch, framed lock photo, blank start without config; log: shell environment resolved (arp-scan via /opt/homebrew/bin), 10 SIGHUPs → 1 reload (75 ms). Not met: reload under 50 ms; next/previous track unverified.
19/11/2026 — DeckOut plan 2 on `deckout-2-app-shell`: `swift test` 127/127 (new T-095–T-118), watched; `scripts/check-bundle.sh` on both variants; two test sessions on this Mac without the owner (registration, foreign client refused, update restart, both decks drawn in the real window via `--snapshot`); plug / unplug and key presses not checked (owner, at UAT).

## Active Work
- UAT of DeckOut (handover above), then signing and release (design phase 7). Backlog: `docs/BACKLOG.md`.

## Completed

### 21/11/2026 — A swipe on the N4's strip makes the next preset live
- **Reference:** `docs/REQUIREMENTS.md` (Saving by the agent; Actions: `next_preset`), `docs/reference/n4.md`,
  `docs/reference/device_quirks.md`; plan `docs/superpowers/plans/2026-11-20-deckout-bl-033-swipe-next-preset.md`
  (gitignored); T-189–T-192 (T-005 changed); BL-033; KI-013, KI-014.
- **For a person:** with the N4's swipe set to `next_preset`, each swipe makes the next preset live, in the file's
  order, wrapping round; the app's menu and a restart follow, because the agent saves the new `active_preset`. Never
  while the Mac is locked. A new N4 made by the app gets the swipe; an existing config gets the line by hand (the app
  has no swipe setting).
- **Decision (owner, 20–21/11/2026):** the `swipe` field keeps its place with a new action; the agent, not the
  daemon, saves the file; no preset name on the deck. KI-013 (a swipe and an app save within milliseconds can lose
  either one) accepted rather than a shared lock file. Both `0x38` and `0x39` count as a swipe, since on this unit
  nearly every swipe comes as `0x38`; a tap in the gap between blocks switches too (KI-014). Two `0x38`s as one swipe
  was turned down: the deck sends one report per swipe.
- **Checked:** run line above. A fresh reviewer: no critical; its important finding (KI-013 said only the swipe could
  be lost) reworded; minors are BL-035–BL-037. On the N4, the first build switched on 18 of ~50 swipes; a timed round
  showed every swipe and every gap tap arriving as `0x38`.

### 20/11/2026 — Monitor brightness moves from where the monitor really is, never jumping to 5 %
- **Reference:** `docs/REQUIREMENTS.md` (External Monitor Brightness), `docs/reference/app.md` (Settings: m1ddc),
  `Vendor/m1ddc/README.md`; T-170–T-173; BL-003.
- **For a person:** the first brightness turn after the agent started, or after 30 s idle, could take a monitor at
  100 % to 5 %. m1ddc read the monitor's reply 10 ms after asking (DDC/CI wants 40) and printed whatever was in the
  buffer: an empty or shifted reply came out as `0`. It now waits 50 ms, takes only a valid reply and asks again;
  the agent reads each monitor on the first turn instead of trusting a start-up reading, and a monitor that gives no
  reading is left alone with "Left: Monitor Error" on screen. Start-up no longer reads the monitors (31 ms, was ~0.4 s).
- **Decision (owner, 20/11/2026):** leave a monitor with no reading alone, saying "Monitor Error" (it covers cases not
  seen yet); patch DeckOut's own m1ddc and ship it in the app; offer the patch upstream afterwards. (CL calls:) a
  reading outside 0–100 counts as none; the HUD shrinks text that wouldn't fit its box, and centres it.
- **Checked:** run line above. Upstream 1.3.2 reads the same way (waydabber/m1ddc#37 notes it); the patch follows
  ddcutil's and MonitorControl's 50 ms wait and reply checks (read at source). A fresh reviewer: no bugs; T-172's
  idle window widened (it could flake under load). Left as is: Switch Monitor pressed within ~50 ms of a turn can
  read the monitor before the turn's write lands (as before), so the next turn starts one step off.

### 20/11/2026 — A reload redraws only the screens that changed, in milliseconds
- **Reference:** `docs/reference/n4.md` (Locked Mac; Running it), `docs/reference/device_quirks.md`,
  `docs/REQUIREMENTS.md` (reload); plan `docs/superpowers/plans/2026-11-20-deckout-bl-005-redraw-changes.md`; T-169;
  BL-005.
- **For a person:** every edit in DeckOut, and every reload from a script, used to redraw all 20 screens (~0.45 s, with
  presses waiting); now only the screens whose picture changed are sent, and a reload with nothing to send takes 7 ms.
  A script that rewrites a key's icon at the same path and posts a reload still shows the new picture (icon files are
  read again every time and compared by content); live blocks are drawn from their latest reading. Unlocking the Mac
  repaints every screen, which puts right a deck that reset itself.
- **Decision (owner, 20/11/2026):** every reload, the app's and outside ones, sends only changes; unlock repaints all.
  (CL calls:) change is judged on the file's bytes, not its path, date or size; an icon that won't decode logs its
  warning once, then stays black until its bytes change.
- **Checked:** run line above. One implementer, read by CL, then a fresh reviewer: no critical or important issues;
  its minor (a failed final packet left slots marked as shown) fixed. Parked: a huge file set as an icon is read in
  full on every reload.

### 20/11/2026 — Seven backlog fixes: strip images follow the tap's app, Stop and Remove can't be undone behind your back, tidier editors
- **Reference:** `docs/reference/app.md` (Launch; Editing; First run and removal), `docs/REQUIREMENTS.md` (XPC);
  plan `docs/superpowers/plans/2026-11-20-deckout-backlog-fixes-1.md`; T-162–T-168 (T-143, T-153, T-156, T-157
  sharpened); BL-006, BL-009, BL-010, BL-013, BL-021, BL-030, BL-032.
- **For a person:** a strip block showing an app's own icon follows its tap to another app, as a key does. An emptied
  Host field pings the default host instead of staying red. Clear sits at the panel's bottom; Save in Edit in
  Window… stands out; a block's text image starts "Block". Stop and Remove says "Stopping…" until macOS has the agent
  out, and a recovery already under way can no longer register it again afterwards. A build without the symbol
  library says so. Behind the scenes: the agent tells only a signature-checked app about changes, and builds the
  ~40 KB live-strip update only when the app is open, once per redraw.
- **Decision (owner, 20/11/2026):** BL-030: only an image that already is an app's own icon follows; a blank block,
  a live reading, or your own picture / text / symbol stays. "Use your judgement" on BL-032: (CL calls) "Block", the
  prominent Save, T-153's no-op half deleted, T-156's hashes replaced by layout checks.
- **Checked:** run line above. One agent per item, each reviewed by CL, then a fresh reviewer over all seven: no
  critical or important issues; its removal-path minor ("Stopping…") fixed test-first. Open: two minors (Try Again
  during a recovery re-registers twice; a late push can mark the link connected after removal), in the ledger.

## History
Older work: `old_progress/README.md`.

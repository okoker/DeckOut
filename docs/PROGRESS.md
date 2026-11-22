# Progress

## Session Handover — 21/11/2026: DeckOut 2.0.0 released (signed, notarised); the decks run on it

### What was done
- Phase 7 (plan `docs/superpowers/plans/2026-11-21-deckout-phase-7-release.md`, gitignored; ledger
  `.superpowers/sdd/2026-11-21-deckout-phase-7-release/progress.md`): signing targets and T-193 (1eef572, 17afc28,
  ad0cc56), README for 2.0.0 (b264653), BL-039 (6f0ba6b). v2.0.0 published 21/11/2026 from ad0cc56, the rc.1 image
  byte for byte; the rc.1 page deleted, its tag kept. The owner's decks moved to the signed app (entry below).
- After the release: README rewritten for DeckOut as it is today (1f1fea4: both decks alike, the app's window, a
  Chrome-on-a-Desktop script, two monitors on one knob, Why DeckOut with the vendors' measured download sizes; no
  hand-editing of the config). 1.0's unused `Info.plist` and launch file removed from the repo root (3ea8848);
  `config.example.json` moved to `Tests/DeckCoreTests/Fixtures/config-decks-no-presets.json` (92795b6). GitHub About
  text and topics updated. Live docs that still described 1.0 brought up to date.

### Uncommitted state
- Only `.DS_Store` and `_user_private/`. Local and gitignored: `signing.mk` (the certificate's SHA-1, the notary
  profile name) and `docs/reference/releasing.md` (the private release how-to).

### Environment state
- The decks run on DeckOut 2.0.0 in `/Applications` (agent `io.github.okoker.deckout.agent`, config
  `~/.config/vsd/config.json`, log `~/Library/Logs/DeckOut/agent.log`); Accessibility and Automation are granted to
  DeckOut.
- DeckOut Dev is removed (`make uninstall-dev`). A dev session: Stop and Remove in DeckOut, `make install-dev`, test,
  `make uninstall-dev`, open DeckOut again. Seed `~/.config/vsd-dev` from `~/.config/vsd` if it's gone.
- Rollback copies, to delete from 28/11/2026 at the owner's go: the retired 1.0 install
  (`~/Library/LaunchAgents/com.streamdeck.controller.plist.retired-by-deckout` and its program),
  `~/.config/vsd.bak-2026-11-21` (the 1.0 config folder) and `~/.config/vsd-dev` (DeckOut Dev's config).
- Signing: the Developer ID certificate is from the original Sub-CA and expires 01/02/2027; a release after that
  needs a G2 certificate (BL-039). Notarising uses the team's notary profile, named in `signing.mk`.

### Still open, recorded only here
- Plan 1 review minors: M1 `script:`/`shortcut:` killed at 30 s like `shell:` (owner's call); M6 `--show-lock-photo`
  ignores reloads; M10 unverified: `NSXPCListener(machServiceName:)` with a name the job doesn't own may crash-loop
  under KeepAlive; M11 unverified: a `.zshrc` touching Documents / Desktop / iCloud prompts in the agent's name.
- Older: the volume tile shows "0%" on outputs with no volume control; knob inputs skip the lock recheck (≤5 s
  window); a deck reconnecting at the lock screen shows its layout ≤5 s before the photo; an unplug mid-redraw logs
  up to 15 warnings.

### What's next
1. Fresh install on the owner's second Mac (macOS 26), phase 7 plan Task 8: from the release page, then removal both
   ways (binning without Stop and Remove, then a logout). Then the README's tested versions and removal advice, and
   `reference/app.md`'s "binned while registered" line.
2. From 28/11/2026: delete the rollback copies (owner's go).
3. macOS 27: the owner's call whether to install on the second Mac before telling friends (KI-016).
4. Then BL-029 (script blocks), once its scripting and scheduling are worked out.

## Current Status
DeckOut 2.0.0 (Developer ID signed, notarised, released 21/11/2026) drives the TreasLin N3 and the MiraBox N4 from
`/Applications` through its own agent; DeckOut Dev is removed and the 1.0 hand install retired. Tested on macOS 15
on this Mac; the owner's second Mac (macOS 26) is next.
21/11/2026 — Phase 7 release on `main`: `make signed VARIANT=release` at ad0cc56 (build 261121.185529), T-193 passing on the real Developer ID build; `make notarize` Accepted in under a minute (HTTP 403 before, until the company team's new agreement was accepted), stapled, `source=Notarized Developer ID`; v2.0.0-rc.1, then v2.0.0 published (sha256 fba1b450…, downloaded back and matched). Owner session moving the decks: Stop and Remove of DeckOut Dev, `make uninstall-dev`, config + 10 icons into `~/.config/vsd` (0 `vsd-dev` mentions, all 20 image paths present), a browser download opened inside the disk image asked to be moved, installed it ran first time (launchd runs = 1, no Constraint lines), 14/14 and 6/6 screens drawn, one Login Items entry, Accessibility via Allow…, the iTerm2 / Chrome-profile / Desktop `osascript` keys asked once per app and then worked, lock photo and swipe fine; an ad hoc XPC client got no reply. Not run: macOS 26 and 27, the bin-while-registered removal.
21/11/2026 — Phase 7, two review minors on `main`: `make -n signed` showed the last disk image deleted only after signing, and a padded `SIGN_ID` reaching `codesign` with its spaces; both checks now pass (image deleted before the build, `SIGN_ID` and `NOTARY_PROFILE` trimmed), and a blank `SIGN_ID` is refused as unset (run only with uncommitted changes, so it stopped before `codesign`); the other refusals unchanged. Nothing built or signed.
21/11/2026 — Phase 7 Task 1 on `main` (signing targets, nothing signed with a certificate): `make app VARIANT=release` failed first at the new Apple Events usage-text check, passes after; T-193 `check-bundle.sh --signed` on the ad hoc release build fails with "not signed with a Developer ID (ad hoc)" while the plain check passes; its parsing read against a scratch ad hoc copy signed with the runtime and the entitlements (the runtime pattern fixed to take `(adhoc,runtime)`); refusals run for real (dev variant, no `SIGN_ID`, uncommitted tree, no `NOTARY_PROFILE`); `make -n signed` signs inside out; a probe disk image built the same way (3.2 MB) mounted with DeckOut.app beside an Applications link, the app inside passing T-107; `make app` (dev) OK; `swift test` 241/241, watched. `make uninstall-dev` only dry-run (`make -n`): DeckOut Dev runs the decks until Task 5. Review fixes: in a scratch harness (fake home, stand-in `launchctl`/`tccutil`), `uninstall-dev` deleted the app while the agent stayed registered, and now refuses and keeps it; with a stand-in `codesign`, T-193 passed a signature lacking the Developer ID marks, and now fails it (the requirement parses in real `codesign`); `swift test` 241/241 again. Two release builds of the same code give the same agent CDHash.
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
19/11/2026 — DeckOut plan 1 on `deckout-1-background`: `swift test` 95/95 (new T-061–T-094); device session with the owner: volume ±5, app/url/open/Shortcut keys, play/pause (QuickTime), preset switch, framed lock photo, blank start without config; log: shell environment resolved (arp-scan via /opt/homebrew/bin), 10 SIGHUPs → 1 reload (75 ms). Not met: reload under 50 ms; next/previous track unverified.
19/11/2026 — DeckOut plan 2 on `deckout-2-app-shell`: `swift test` 127/127 (new T-095–T-118), watched; `scripts/check-bundle.sh` on both variants; two test sessions on this Mac without the owner (registration, foreign client refused, update restart, both decks drawn in the real window via `--snapshot`); plug / unplug and key presses not checked (owner, at UAT).

## Active Work
- Phase 7 close-out: the second-Mac install (macOS 26), then the README's tested versions. Backlog: `docs/BACKLOG.md`.

## Completed

### 21/11/2026 — DeckOut 2.0.0 is out: one signed, notarised download, and the owner's decks run on it
- **Reference:** `docs/reference/app.md` (Signing and release; Debug builds), `README.md`; plan
  `docs/superpowers/plans/2026-11-21-deckout-phase-7-release.md`; T-193; BL-039; KI-015–KI-017.
- **For a person:** a friend downloads `DeckOut-2.0.0.dmg` from GitHub Releases, drags DeckOut to Applications and
  opens it with only macOS's usual "downloaded from the internet" question. The README explains installing,
  permissions (Accessibility, not Input Monitoring as 1.0 said), coming from 1.0, updating and removing. Keys that
  drive other apps through `osascript` still work under the signed build: macOS asks once per app.
- **Decision (owner, 21/11/2026):** a disk image, not a zip; candidates as public pre-releases; test on macOS 15 and
  26, then release ("dont overcomplicate a pet project"), publishing before the 26 install; DeckOut Dev removed
  everywhere, back only for a dev session; the signed update test waits for the first release that changes the
  agent (BL-039: builds of the same code give an identical agent); rollback copies kept a week.
- **Checked:** run line above. A fresh opus review of the signing targets: two important fixes made test-first
  (`uninstall-dev` with the agent still registered; T-193 passing any team's signature), two minors fixed at the
  owner's word, the rest in the ledger. Seen on the decks: after Stop and Remove the N3 keeps its last pictures
  (KI-015); the downloaded agent plist carries the quarantine flag (KI-016, macOS 27).

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

## History
Older work: `old_progress/README.md`.

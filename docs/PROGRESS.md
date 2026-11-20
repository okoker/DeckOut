# Progress

## Session Handover — 20/11/2026: eight backlog fixes on top of the UAT fixes; the owner re-tests both

### What was done
- DeckOut phases 2–6 are on chained local branches (`deckout-2-app-shell` → … → `deckout-6-settings`); the owner's
  first UAT issues are fixed on `deckout-7-uat-fixes` (plan 7, from `deckout-6-settings`): BL-026 command field,
  BL-027 strip images, BL-028 / BL-011 presets. Then, on the same branch, seven backlog fixes (one commit each):
  BL-006, BL-009, BL-010, BL-030, BL-013, BL-021, BL-032; then BL-005 (a reload sends only the screens that changed).
  Installed to `~/Applications/DeckOut Dev.app`. Not pushed, merged or signed. Rulings per plan:
  `.superpowers/sdd/<plan>/progress.md`.

### The owner's checks (quit and reopen DeckOut Dev first: the new app restarts the agent)
- Command: type in the panel without Return, click Edit in Window…: the typing is there; Save (⌘Return, now the
  blue button) applies, Esc cancels; `' " --` and command words stay as typed in both.
- Strip: a block shows Tap first, then Shows → An image → Text / Library / Image, drawn wide on the N4. A block
  showing Notes' own icon, its tap changed to another app, shows that app's icon (BL-030); a text image on a block
  with no tap starts as "Block". An internet block's Host emptied goes back to one.one.one.one and turns green.
- Every editor: Clear Key / Block / Knob sits at the bottom of the panel, with no stray scroll.
- Change one key's icon on each deck: only that screen redraws (the agent log says `Drew 1 of 6` / `Drew 1 of 14`);
  lock and unlock: every screen is sent again (`Drew 14 of 14`).
- Presets: New Preset… → Cancel adds nothing; Return creates; a taken name greys out Create with the reason; Rename;
  the menu order; the name selected when the sheet opens; Save and Create look right (snapshots can't show them).

### Environment state — the decks now run on DeckOut Dev
- The hand install is retired: `~/Library/LaunchAgents/com.streamdeck.controller.plist.retired-by-deckout` (its
  program is still in `~/Library/Application Support/StreamDeckController/`). The dev agent is registered and drives
  both decks (`io.github.okoker.deckout.dev.agent`, debug build, ad hoc; config `~/.config/vsd-dev/config.json`, a copy
  of the live one; log `~/Library/Logs/DeckOut Dev/agent.log`). Accessibility for it is probably not granted yet.
- Rollback to the hand install: DeckOut Dev → Settings → Stop and Remove; then `mv` the `.retired-by-deckout` plist
  back and `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.streamdeck.controller.plist`.
- Test sessions: the dev agent is the live controller, and stays so while fixing (owner, 20/11/2026: the decks
  going blank during an install is fine). `make install-dev` replaces what runs the owner's decks (the app restarts
  the agent on the new build).

### Gotchas
- KI-008: replacing the bundle (`make install-dev`, registered or not) can get the agent's next start killed by a
  launch constraint; the app unregisters and registers afresh by itself after 10 s ("registered again" in its
  output), so the decks are dark ~10 s after an install.
- A reload sends only the screens whose image changed, so it no longer repaints a deck showing something stale;
  locking and unlocking the Mac, or replugging, does. Stale keys during UAT more likely mean a second agent drawing.
- `--selftest` ends with Stop and Remove (it leaves the dev agent unregistered): don't run it while the owner uses
  DeckOut Dev for their decks.
- Tests: `ImageRenderer` draws AppKit controls as yellow placeholders (use `Snapshot.windowPNG`); read tile pixels as
  sRGB bytes (`NSBitmapImageRep.colorAt` goes through generic RGB); `#expect` can't take mutating calls or deep
  double-optionals; snapshot tests starve the main thread, so XPC / link waits are 10 s.

### Recorded only here (still open)
- Plan 1 review minors: M1 `script:`/`shortcut:` killed at 30 s like `shell:` (owner's call); M6 `--show-lock-photo`
  ignores reloads; M10 unverified: `NSXPCListener(machServiceName:)` with a name the job doesn't own may crash-loop
  under KeepAlive; M11 unverified: a `.zshrc` touching Documents / Desktop / iCloud prompts in the agent's name.
- Older: the volume tile shows "0%" on outputs with no volume control; knob inputs skip the lock recheck (≤5 s
  window); a deck reconnecting at the lock screen shows its layout ≤5 s before the photo; an unplug mid-redraw logs
  up to 15 warnings.
- Signing: check which authority issued the Developer ID certificate before the first signed build (only builds after
  01/02/2027 need a G2 one).

### What's next
1. The owner re-tests plan 7, then the rest of UAT (plug / unplug; every editor; presets; ⌘Z in fields;
   Accessibility; lock photo gestures; Settings); fixes on `deckout-7-uat-fixes`, tests first.
2. Then merge, signing, release (design phase 7). Next: live strip blocks people add (BL-029), designed first.

## Current Status
DeckOut Dev (`~/Applications`, a debug build of `deckout-7-uat-fixes`) drives the TreasLin N3 and the MiraBox N4
through its own agent; the hand install is retired. The app (design phases 2–6, plus the UAT fixes) is in the owner's
UAT: it runs the deck controller from its bundle, edits every control, presets, brightness, the lock photo, generated
icons, monitors and its own removal.
20/11/2026 — BL-005 on `deckout-7-uat-fixes` (to 38094e3): `swift test` 217/217 (new T-169), watched; `make install-dev` (build 261120.103217), one `--snapshot` run: KI-008 on the restart, the app re-registered 10 s later, window "Deck controller running"; the agent drew 6 of 6 and 14 of 14 on connect; one `--post-reload` with nothing changed: "Drew 0 of 6 slots on n3 in 1 ms", "Drew 0 of 14 slots on n4 in 4 ms", "Reloaded in 7 ms" (433–453 ms before). Not checked: a changed key and an unlock on the decks (owner, at UAT).
20/11/2026 — Seven backlog fixes on `deckout-7-uat-fixes` (to 1b615ac): `swift test` 210/210 (new T-162–T-168), watched; `make install-dev` (build 261120.035630), then one `--snapshot` run of the real app: it asked the old agent to restart, the new one hit KI-008 and the app's own recovery re-registered it 10 s later; the window said "Deck controller running" (the new agent's build), and the agent drew the N3 and the N4's lock photo (Mac locked). Not checked: live strip pushes (paused while locked), every click (owner, at UAT).
20/11/2026 — DeckOut plan 7 on `deckout-7-uat-fixes`: `swift test` 198/198 (new T-153–T-161; T-132 changed), watched; `make install-dev` installed it. Not checked: the clicks in the real window (owner, at UAT; the app was theirs and open).
19/11/2026 — DeckOut plan 1 on `deckout-1-background`: `swift test` 95/95 (new T-061–T-094); device session with the owner: volume ±5, app/url/open/Shortcut keys, play/pause (QuickTime), preset switch, framed lock photo, blank start without config; log: shell environment resolved (arp-scan via /opt/homebrew/bin), 10 SIGHUPs → 1 reload (75 ms). Not met: reload under 50 ms; next/previous track unverified.
20/11/2026 — DeckOut plan 6 on `deckout-6-settings`: `swift test` 185/185 (new T-144–T-152), watched; test sessions 6–7: `--selftest` 23/23 (the app's own m1ddc lists "LG HDR 4K · Left / Right", both answer a brightness read; Stop and Remove stays removed 15 s later with launchd holding no job); the old-controller screen in the real window. Not checked: Retire It on the real plist, Settings by hand (owner, at UAT).
19/11/2026 — DeckOut plan 2 on `deckout-2-app-shell`: `swift test` 127/127 (new T-095–T-118), watched; `scripts/check-bundle.sh` on both variants; two test sessions on this Mac without the owner (registration, foreign client refused, update restart, both decks drawn in the real window via `--snapshot`); plug / unplug and key presses not checked (owner, at UAT).

## Active Work
- UAT of DeckOut (handover above), then merge, signing and release (design phase 7). Backlog: `docs/BACKLOG.md`.

## Completed

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

### 20/11/2026 — Long commands can be read and edited, strip blocks take images like keys, presets can be cancelled
- **Reference:** `docs/reference/app.md` (Actions; Run Command; Strip blocks; Presets); plan
  `docs/superpowers/plans/2026-11-20-deckout-7-uat-fixes.md`; T-153–T-161 (T-132 changed); BL-029–BL-032.
- **For a person:** a command shows whole in the editor (full width, wrapped, up to ten lines), and Edit in Window…
  opens it wide; nothing typed is turned into curly quotes or "corrected". Multi-line fields, the text image's too,
  show more than one line at last. A strip block reads like a key: what a tap does, then what it shows: an image (a
  picture, text or a symbol on a colour, drawn to the strip's wide shape) or a live reading. The preset pull-down
  never disappears: New Preset… and Rename… ask for the name in a small sheet you can cancel.
- **Decision (owner, 20/11/2026):** the command gets a full-width field plus a window; strip blocks get the key's image
  choices and stay blank until one is picked; "An image", not "An icon"; the menu: live preset, Default, New Preset,
  Rename, Duplicate, Delete, a line, the rest; live readings people add come from a folder, not the app (BL-029).
  (CL calls, ledger:) strip tiles 352 × 224; the preset sheets hang off the main window.
- **Checked:** `swift test` 198/198, installed. Building found why the command couldn't be read: multi-line fields
  drew on one line (the rounded-border style). A fresh reviewer found every field autocorrecting typed words, the
  command's included: fixed test-first. Its minors are BL-030–BL-032.

### 20/11/2026 — DeckOut takes over from the hand install, ships m1ddc, and has Settings
- **Reference:** `docs/reference/app.md` (First run and removal; Settings); plan
  `docs/superpowers/plans/2026-11-19-deckout-6-settings-first-run.md`; T-144–T-152; BL-024–BL-025.
- **For a person:** nothing to install for monitor brightness: DeckOut carries m1ddc. Settings lists your monitors,
  tells two identical ones apart as Left and Right, checks each answers, and lets you name them and set the order the
  Switch Monitor key goes through. On first open DeckOut offers to retire the hand-installed controller (kept, so it
  can be put back). Stop and Remove takes DeckOut out of Login Items for removal.
- **Decision (owner, 19/11/2026):** m1ddc vendored from source (1.3.1; 1.3.2 was a day old). (CL calls:) retiring
  moves the plist aside rather than deleting it; the README's install text changes when the app ships.
- **Checked:** `swift test` 185/185; sessions 6–7 (run line above). A fresh reviewer found Stop and Remove quietly
  undone by the app's own recovery (critical), monitor reordering that showed nothing, and silent non-answering
  monitors; all fixed test-first, and the removal fix proven live.


## History
Older work: `old_progress/README.md`.

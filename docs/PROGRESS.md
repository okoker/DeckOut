# Progress

## Session Handover — 20/11/2026 02:35: UAT fixes built and installed; the owner re-tests them

### What was done
- DeckOut phases 2–6 are on chained local branches (`deckout-2-app-shell` → … → `deckout-6-settings`); the owner's
  first UAT issues are fixed on `deckout-7-uat-fixes` (plan 7, from `deckout-6-settings`): BL-026 command field,
  BL-027 strip images, BL-028 / BL-011 presets. Installed to `~/Applications/DeckOut Dev.app`. Not pushed, merged
  or signed. Rulings per plan: `.superpowers/sdd/<plan>/progress.md`; deferred minors BL-006–BL-025, BL-030–BL-032.

### The owner's checks for plan 7 (quit and reopen DeckOut Dev first: the new app restarts the agent)
- Command: type in the panel without Return, click Edit in Window…: the typing is there; Save (⌘Return) applies,
  Esc cancels; `' " --` and command words stay as typed in both.
- Strip: a block shows Tap first, then Shows → An image → Text / Library / Image, drawn wide on the N4.
- Presets: New Preset… → Cancel adds nothing; Return creates; a taken name greys out Create with the reason; Rename;
  the menu order; the name selected when the sheet opens; Save and Create look right (snapshots can't show them).
- BL-030 needs the owner's call (a strip block's App image when the tap's app changes).

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
- KI-008: installing over an unregistered dev agent then registering kills the first start; the app now unregisters
  and registers afresh by itself after 10 s ("registered again" in its output). Reinstalling while registered is fine.
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
20/11/2026 — DeckOut plan 7 on `deckout-7-uat-fixes`: `swift test` 198/198 (new T-153–T-161; T-132 changed), watched; `make install-dev` installed it. Not checked: the clicks in the real window (owner, at UAT; the app was theirs and open).
19/11/2026 — DeckOut plan 1 on `deckout-1-background`: `swift test` 95/95 (new T-061–T-094); device session with the owner: volume ±5, app/url/open/Shortcut keys, play/pause (QuickTime), preset switch, framed lock photo, blank start without config; log: shell environment resolved (arp-scan via /opt/homebrew/bin), 10 SIGHUPs → 1 reload (75 ms). Not met: reload under 50 ms; next/previous track unverified.
20/11/2026 — DeckOut plan 6 on `deckout-6-settings`: `swift test` 185/185 (new T-144–T-152), watched; test sessions 6–7: `--selftest` 23/23 (the app's own m1ddc lists "LG HDR 4K · Left / Right", both answer a brightness read; Stop and Remove stays removed 15 s later with launchd holding no job); the old-controller screen in the real window. Not checked: Retire It on the real plist, Settings by hand (owner, at UAT).
20/11/2026 — DeckOut plan 5 on `deckout-5-icons`: `swift test` 172/172 on the branch (new T-139–T-143), watched; test session 5: `--selftest` passed with a text and a symbol tile drawn by the real app's bundled library; the app recovered from KI-008 by itself. Not checked: the pickers by hand (owner, at UAT).
20/11/2026 — DeckOut plan 4 on `deckout-4-lock-photo`: `swift test` 161/161 (new T-134–T-138), watched; test session 4: `--selftest` passed with a generated lock photo moved while the N4 previewed it (agent: one decode, 17–33 ms per preview), Done back to keys, all undone; real-window snapshot of photo mode. Not checked: real drag / pinch / scroll (owner, at UAT).
19/11/2026 — DeckOut plan 2 on `deckout-2-app-shell`: `swift test` 127/127 (new T-095–T-118), watched; `scripts/check-bundle.sh` on both variants; two test sessions on this Mac without the owner (registration, foreign client refused, update restart, both decks drawn in the real window via `--snapshot`); plug / unplug and key presses not checked (owner, at UAT).

## Active Work
- UAT of DeckOut (handover above), then merge, signing and release (design phase 7). Backlog: BL-002–BL-032.

## Completed

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

### 20/11/2026 — Keys can show text or a symbol on a colour, made in DeckOut
- **Reference:** `docs/reference/app.md` (Icons); plan `docs/superpowers/plans/2026-11-19-deckout-5-icons.md`;
  T-139–T-143; BL-020–BL-023.
- **For a person:** besides an app's icon or your own picture, a key can show a word or two (wrapped, sized to fit)
  or one of 1,530 symbols, on one of ten colours, with the text colour picked to read well. The key remembers how its
  icon was made, so you can change the words or the colour later.
- **Decision (owner, 19/11/2026):** the Phosphor library (MIT). (CL calls:) ten swatches and Auto / White / Black
  instead of a colour well; tiles drawn by the app, the agent still draws a file.
- **Checked:** `swift test` 172/172; test session 5 (run line above). A fresh reviewer found symbols drawn off-centre
  and long text going unreadable, plus a typo in a tile able to stop the agent loading the file: all fixed test-first.

### 20/11/2026 — The N4's lock photo is chosen, moved and zoomed in DeckOut, live on the deck
- **Reference:** `docs/reference/app.md` (Lock photo mode); plan `docs/superpowers/plans/2026-11-19-deckout-4-lock-photo.md`;
  T-134–T-138; BL-016–BL-019.
- **For a person:** Lock Photo… turns the window into the N4 showing your photo across its screens, exactly as it
  will be cut; drag to move it, pinch or scroll to zoom, see what falls between the screens if you like. The real
  N4 shows it as you go and goes back to its keys when you click Done. The app keeps its own copy of the photo.
- **Decision (owner, 19/11/2026):** the approved mockup. (CL calls:) chosen photos are saved at most 3200 px as a
  JPEG; files over 100 MB are refused; the zoom slider spans 100–400 % (pinch reaches 1000 %).
- **Checked:** `swift test` 161/161; test session 4 (run line above). A fresh reviewer found four important issues
  (a dead zone within a drag; the N4 left on the photo after unplugging; undo not reaching the N4; huge photos),
  fixed test-first.

## History
Older work: `old_progress/README.md`.

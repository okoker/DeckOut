# Progress

## Session Handover — 19/11/2026 (late night, owner away)

**Autonomous run to UAT** (owner, 19/11/2026): build DeckOut through phase 6 while the owner is away, then UAT.
Standing go for live test sessions (stop the installed daemon → register the dev agent on a copy of the config →
test → unregister → start the installed daemon again and check it). Commits on local branches, not pushed or merged
until UAT. No signing. Downloads allowed: m1ddc source, Phosphor icons. Plans and ledgers:
`docs/superpowers/plans/2026-11-19-deckout-{2,3}-*.md`, `.superpowers/sdd/<plan>/progress.md`.

### Where it stands
- Plan 2 (the app shell) built on `deckout-2-app-shell`: 127 tests, two test sessions, fresh review fixed (I1, I2);
  minors are BL-006–BL-010. Plan 3 (editing) built on `deckout-3-editing` (from plan 2's branch): 152 tests, test
  session 3 (`--selftest` 12/12), fresh review fixed (I1–I3, M1, M7); minors BL-011–BL-015. Plan 4 (lock photo) built on
  `deckout-4-lock-photo`: 161 tests, session 4 (`--selftest` with a lock photo), review fixed (I1–I4, M2, M4);
  minors BL-016–BL-019. Plan 5 (icons) built on
  `deckout-5-icons`: 172 tests, session 5, review fixed (I1, I2, M1–M3, M8); minors BL-020–BL-023. Next: plan 6
  (settings, monitors, first run) on `deckout-6-settings`; its vendored m1ddc and first pieces sit uncommitted in the
  tree until that branch. Downloads verified and parked in the session scratchpad:
  Phosphor 2.1.2 (npm sha512 matched), m1ddc 1.3.1 (Homebrew's sha256 matched; 1.3.2 is a day old, not adopted).
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
20/11/2026 — DeckOut plan 5 on `deckout-5-icons`: `swift test` green (new T-139–T-143), watched; test session 5: `--selftest` passed with a text and a symbol tile drawn by the real app's bundled library; the app recovered from KI-008 by itself. Not checked: the pickers by hand (owner, at UAT).
20/11/2026 — DeckOut plan 4 on `deckout-4-lock-photo`: `swift test` 161/161 (new T-134–T-138), watched; test session 4: `--selftest` passed with a generated lock photo moved while the N4 previewed it (agent: one decode, 17–33 ms per preview), Done back to keys, all undone; real-window snapshot of photo mode. Not checked: real drag / pinch / scroll (owner, at UAT).
20/11/2026 — DeckOut plan 3 on `deckout-3-editing`: `swift test` 152/152 (new T-119–T-133), watched; test session 3 on this Mac without the owner: `--selftest` 12/12 against the live dev agent (key set and saved, Test ran `echo` in the agent, preset made live then deleted, brightness drag one undo, all undone), the app recovered from KI-008 by itself, update restart; real-window snapshots of the editors. Not checked: clicks, typing, focus (owner, at UAT).
19/11/2026 — DeckOut plan 2 on `deckout-2-app-shell`: `swift test` 127/127 (new T-095–T-118), watched; `scripts/check-bundle.sh` on both variants; two test sessions on this Mac without the owner (registration, foreign client refused, update restart, both decks drawn in the real window via `--snapshot`); plug / unplug and key presses not checked (owner, at UAT).

## Active Work
- DeckOut plan 6, settings / monitors / first run (`docs/superpowers/plans/2026-11-19-deckout-6-settings-first-run.md`),
  then UAT. Backlog: BL-002–BL-023.

## Completed

### 20/11/2026 — Keys can show text or a symbol on a colour, made in DeckOut
- **Reference:** `docs/reference/app.md` (Icons); plan `docs/superpowers/plans/2026-11-19-deckout-5-icons.md`;
  T-139–T-143; BL-020–BL-023.
- **For a person:** besides an app's icon or your own picture, a key can show a word or two (wrapped, sized to fit)
  or one of 1,530 symbols, on one of ten colours, with the text colour picked to read well. The key remembers how its
  icon was made, so you can change the words or the colour later.
- **Decision (owner, 19/11/2026):** the Phosphor library (MIT). (CL calls:) ten swatches and Auto / White / Black
  instead of a colour well; tiles drawn by the app, the agent still draws a file.
- **Checked:** `swift test` green; test session 5 (run line above). A fresh reviewer found symbols drawn off-centre
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

### 20/11/2026 — Every control of both decks is set from DeckOut, and changes show on the deck at once
- **Reference:** `docs/reference/app.md` (Editing); plan `docs/superpowers/plans/2026-11-19-deckout-3-editing.md`;
  T-119–T-133; BL-011–BL-015.
- **For a person:** click a key, button, knob or strip block and set what it does from a menu: open an app, a
  website or a file, a keyboard shortcut (press it to record it), one of your Shortcuts, media keys, volume and
  monitor brightness steps, a script or a command. Keys take the app's icon or your picture. Test runs it right there
  and shows what happened. Presets are made, switched, renamed and deleted from the toolbar, with a brightness slider
  beside them; ⌘Z undoes anything. Keys whose app or script has gone are marked red. When a shortcut needs
  Accessibility, the app says so and opens the right pane.
- **Decision (owner, 19/11/2026):** the unmocked editor screens follow the approved mockups' style (CL designed);
  judged at UAT. (CL calls, in the plan / ledger:) the app keeps its own undo history of whole configs; a hand edit
  picked up starts it again; pictures are imported at most 512 px.
- **Checked:** `swift test` 152/152; test session 3 (run line above). A fresh reviewer found three important issues
  (edits blocked after a fixed problem; undo dropping a hand edit; phone photos coming out black), fixed test-first,
  plus two re-graded minors (a frozen slider in debug builds; a field re-committing after undo).

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

## History
Older work: `old_progress/README.md`.

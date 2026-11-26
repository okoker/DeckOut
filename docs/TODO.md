# TODO — Active Sprint

Current build focus. Done + committed = delete the line.

---

- [P1] [debt] Settings folder `~/.config/vsd` → `~/.deckout` (DeckOut Dev: `~/.config/vsd-dev` → `~/.deckout-dev`),
  missed in the DeckOut rename. Code: `AppIdentity.configPath`, `ConfigFile.candidates` (the hand-install
  fallback), `AppModel+Settings` (the folder named in messages), their tests and the fixture's `lock_photo`;
  Makefile comments; README, REQUIREMENTS, TESTS T-073, `reference/app.md`, `reference/n4.md`.
  Move this Mac's setup by hand, once, and only when the build that reads the new folder replaces DeckOut 2.0.0
  (2.0.0 reads the old one: moved earlier, the decks go blank and its next save starts a second folder): stop
  DeckOut, move the folder, rewrite the icon and lock-photo paths inside `config.json` (they are absolute and name
  `/.config/vsd/`), then check no `vsd` is left in it and every image path exists. No migration in the app and
  nothing for other installs (owner, 26/11/2026): the README's "your settings carry over" lines (Removing, Coming
  from 1.0, History) change with it.
- [P2] [debt] Other `streamdeck` names left from 1.0. The reload signal `com.streamdeck.controller.reload`
  (`Daemon.reloadNotification`) → per variant, `<agent label>.reload`, so a `--post-reload` for DeckOut Dev stops
  reloading DeckOut too; its only sender is `DeckOutAgent --post-reload`, in the same binary as the listener, so
  nothing outside breaks (REQUIREMENTS line on it). Queue names `streamdeck.*` → `deckout.*`
  (`ActionDispatcher`, `BrightnessControl`, `LatencyProbe`; seen only in crash reports). Photos
  `docs/assets/streamdeck.jpg` / `streamdeck-n4.jpg` → named for the N3 / N4, with README, `DeckFace` comment and the
  two `.gitignore` exceptions (`*.jpg` is ignored: a stale exception leaves a re-added photo silently out of git).
  Keep: `com.streamdeck.controller` in `OldController` (how DeckOut finds a 1.0 install), the history mentions,
  the makers' names (VSD Craft, VSDinside, firmware `VSDN3`). Where an old name stays and nothing says why, add that
  1.0 was StreamDeckController and the app is now DeckOut: `OldController.label`, the `AppIdentity` init comment,
  `reference/app.md` (the hand-installed controller).
- [P2] [debt] Local folder `vsd_display` → `deckout` (owner, between sessions; nothing in the repo names it). Then
  move Claude's folder `~/.claude/projects/-Users-omer-Desktop--playground-utilities-vsd-display` to the new
  folder's name, or its project notes are left behind.

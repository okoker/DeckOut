# 16 — DeckOut BL-033: a swipe on the N4 makes the next preset live (21/11/2026)

Moved out of `PROGRESS.md` on 26/11/2026.

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

Run line:
21/11/2026 — BL-033 on `main` (3582782, 5e479ff, then the `0x38` fix): `swift test` 241/241 (new T-189–T-192), watched; T-191 failed with the hand-off moved above the lock check. `make install-dev` (build 261121.000629); the owner's N4 swipe set to `next_preset` by hand (backup `~/.config/vsd-dev/config.json.bak-2026-11-21`); the agent restarted on it without KI-008. Owner's swipes: 18 switched, 26 came as `0x38` and were ignored; timed round: every swipe and gap tap `0x38`. Fix: T-005 failed first (`0x38` decoded to nothing), 241/241 after; build 261121.012023: 9 of 9 swipes switched. Owner, later: a locked Mac ignores swipes (four "ignored while locked" in the log); swiping steps through the presets. Not checked: the app's preset menu following a swipe.

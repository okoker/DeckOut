# 14 — DeckOut BL-005: a reload redraws only the screens that changed (20/11/2026)

Moved out of `PROGRESS.md` on 26/11/2026.

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

Run line:
20/11/2026 — BL-005 on `deckout-7-uat-fixes` (to 38094e3): `swift test` 217/217 (new T-169), watched; `make install-dev` (build 261120.103217), one `--snapshot` run: KI-008 on the restart, the app re-registered 10 s later, window "Deck controller running"; the agent drew 6 of 6 and 14 of 14 on connect; one `--post-reload` with nothing changed: "Drew 0 of 6 slots on n3 in 1 ms", "Drew 0 of 14 slots on n4 in 4 ms", "Reloaded in 7 ms" (433–453 ms before). Not checked: a changed key and an unlock on the decks (owner, at UAT).

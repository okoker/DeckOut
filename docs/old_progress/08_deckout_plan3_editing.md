# 08 — DeckOut plan 3: editing (20/11/2026)

Moved out of `PROGRESS.md` on 20/11/2026.

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

Run line: 20/11/2026 — DeckOut plan 3 on `deckout-3-editing`: `swift test` 152/152 (new T-119–T-133), watched; test session 3 on this Mac without the owner: `--selftest` 12/12 against the live dev agent (key set and saved, Test ran `echo` in the agent, preset made live then deleted, brightness drag one undo, all undone), the app recovered from KI-008 by itself, update restart; real-window snapshots of the editors. Not checked: clicks, typing, focus (owner, at UAT).

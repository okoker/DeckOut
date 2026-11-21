# 12 — DeckOut plan 7: UAT fixes, long commands, strip images, preset sheets (20/11/2026)

Moved out of `PROGRESS.md` on 21/11/2026.

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

Run line: 20/11/2026 — DeckOut plan 7 on `deckout-7-uat-fixes`: `swift test` 198/198 (new T-153–T-161; T-132 changed), watched; `make install-dev` installed it. Not checked: the clicks in the real window (owner, at UAT; the app was theirs and open).

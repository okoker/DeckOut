# 10 — DeckOut plan 5: icons (20/11/2026)

Moved out of `PROGRESS.md` on 20/11/2026.

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

Run line: 20/11/2026 — DeckOut plan 5 on `deckout-5-icons`: `swift test` 172/172 on the branch (new T-139–T-143), watched; test session 5: `--selftest` passed with a text and a symbol tile drawn by the real app's bundled library; the app recovered from KI-008 by itself. Not checked: the pickers by hand (owner, at UAT).

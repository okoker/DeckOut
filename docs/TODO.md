# TODO — Active Sprint

Current build focus. Done + committed = delete the line.

---

- [P1] [debt] Move this Mac's setup from `~/.config/vsd` to `~/.deckout`, once, by hand, when a build from `main`
  (which reads only `~/.deckout`) replaces DeckOut 2.0.0. Not earlier: 2.0.0 reads the old folder, so the decks would
  go blank and its next save would start a second folder. Stop DeckOut, move the folder, rewrite the icon and
  lock-photo paths inside `config.json` (absolute, naming `/.config/vsd/`), check no `vsd` is left in it and every
  image path exists, then install and open the new build. Then the memory notes and PROGRESS's environment state.
- [P2] [debt] Local folder `vsd_display` → `deckout` (owner, between sessions; nothing in the repo names it). Then
  move Claude's folder `~/.claude/projects/-Users-omer-Desktop--playground-utilities-vsd-display` to the new
  folder's name, or its project notes are left behind.

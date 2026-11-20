# 11 — DeckOut plan 6: Settings, bundled m1ddc, first run (20/11/2026)

Moved out of `PROGRESS.md` on 20/11/2026.

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

Run line: 20/11/2026 — DeckOut plan 6 on `deckout-6-settings`: `swift test` 185/185 (new T-144–T-152), watched; test sessions 6–7: `--selftest` 23/23 (the app's own m1ddc lists "LG HDR 4K · Left / Right", both answer a brightness read; Stop and Remove stays removed 15 s later with launchd holding no job); the old-controller screen in the real window. Not checked: Retire It on the real plist, Settings by hand (owner, at UAT).

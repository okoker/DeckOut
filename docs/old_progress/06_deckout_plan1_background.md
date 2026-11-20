# 06 — DeckOut plan 1: the background part (19/11/2026)

Moved out of `PROGRESS.md` on 20/11/2026.

### 19/11/2026 — The daemon is ready for the DeckOut app: presets, photo framing, new actions, no reload stall
- **Reference:** design `docs/design/config_app.md` (phases 0–1; plan 1 built); `docs/REQUIREMENTS.md` (Configuration,
  Actions, Daemon Behaviour); `docs/reference/n4.md`; `docs/reference/device_quirks.md` (media keys); T-061–T-094.
- **For a person:** a reload no longer freezes the decks while the monitors are read, and a burst of saves redraws
  once. Each deck can hold several layouts (presets), one of them live. Keys can open an app, a website, a file or
  folder, run a script or one of Apple's Shortcuts, or play / pause / skip; volume and monitor keys take a step. The
  lock photo can be zoomed and moved. Commands find Homebrew tools (your own shell's PATH). With no usable config the
  daemon runs with blank decks and says why, instead of crash-looping. All set by hand in the JSON until the app exists.
- **Decision (owner, 19/11/2026):** built natively on a branch, merged and pushed to GitHub (no release tag), then
  installed as the daemon. The rename to DeckOut waits for plan 2. A reload's full redraw (75–158 ms) stays for now
  as BL-005. The XPC service takes any caller running as the owner until plan 2's signing check; nothing starts it yet.
- **Checked:** `swift test` 95/95; a fresh reviewer's three important findings fixed test-first. Device session with
  the owner (run line in Current Status): every new action kind, presets, the framed lock photo, a blank start, the
  layout kept when the file went missing. Next / previous track unverified (no track player here); the owner's
  network script needs a terminal, so `script:` can't run it.

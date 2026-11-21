# 13 — DeckOut backlog fixes 1: strip images follow the tap's app, Stop and Remove holds (20/11/2026)

Moved out of `PROGRESS.md` on 21/11/2026.

### 20/11/2026 — Seven backlog fixes: strip images follow the tap's app, Stop and Remove can't be undone behind your back, tidier editors
- **Reference:** `docs/reference/app.md` (Launch; Editing; First run and removal), `docs/REQUIREMENTS.md` (XPC);
  plan `docs/superpowers/plans/2026-11-20-deckout-backlog-fixes-1.md`; T-162–T-168 (T-143, T-153, T-156, T-157
  sharpened); BL-006, BL-009, BL-010, BL-013, BL-021, BL-030, BL-032.
- **For a person:** a strip block showing an app's own icon follows its tap to another app, as a key does. An emptied
  Host field pings the default host instead of staying red. Clear sits at the panel's bottom; Save in Edit in
  Window… stands out; a block's text image starts "Block". Stop and Remove says "Stopping…" until macOS has the agent
  out, and a recovery already under way can no longer register it again afterwards. A build without the symbol
  library says so. Behind the scenes: the agent tells only a signature-checked app about changes, and builds the
  ~40 KB live-strip update only when the app is open, once per redraw.
- **Decision (owner, 20/11/2026):** BL-030: only an image that already is an app's own icon follows; a blank block,
  a live reading, or your own picture / text / symbol stays. "Use your judgement" on BL-032: (CL calls) "Block", the
  prominent Save, T-153's no-op half deleted, T-156's hashes replaced by layout checks.
- **Checked:** run line above. One agent per item, each reviewed by CL, then a fresh reviewer over all seven: no
  critical or important issues; its removal-path minor ("Stopping…") fixed test-first. Open: two minors (Try Again
  during a recovery re-registers twice; a late push can mark the link connected after removal), in the ledger.

Run line:
20/11/2026 — Seven backlog fixes on `deckout-7-uat-fixes` (to 1b615ac): `swift test` 210/210 (new T-162–T-168), watched; `make install-dev` (build 261120.035630), then one `--snapshot` run of the real app: it asked the old agent to restart, the new one hit KI-008 and the app's own recovery re-registered it 10 s later; the window said "Deck controller running" (the new agent's build), and the agent drew the N3 and the N4's lock photo (Mac locked). Not checked: live strip pushes (paused while locked), every click (owner, at UAT).

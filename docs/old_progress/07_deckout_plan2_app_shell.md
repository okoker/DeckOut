# 07 — DeckOut plan 2: the app shell (19/11/2026)

Moved out of `PROGRESS.md` on 20/11/2026.

### 19/11/2026 — DeckOut is an app: it runs the deck controller and shows your deck as it is
- **Reference:** `docs/reference/app.md` (new); design `docs/design/config_app.md` (phase 2); plan
  `docs/superpowers/plans/2026-11-19-deckout-2-app-shell.md`; T-095–T-118; KI-008 (rewritten); BL-006–BL-010.
- **For a person:** DeckOut.app holds the deck controller, renamed DeckOutAgent, and starts it at login through
  macOS's Login Items; no Terminal. Open the app and it shows the deck that's plugged in, drawn as it looks, with the
  live strip moving; both plugged in, it asks which; none, it asks you to plug one in. It says when it's in the wrong
  folder, switched off in Login Items, or can't reach the controller. Only DeckOut's own app can talk to the
  controller. Nothing is editable yet (plan 3).
- **Decision (owner, 19/11/2026):** build through phase 6 unattended, with test sessions on this Mac and local
  commits; UAT at the end. (CL calls, in the plan:) ad hoc builds pin the app's exact binary; the app restarts an
  agent of another build once; the dev variant has its own config and logs and installs to `~/Applications`.
- **Checked:** `swift test` 127/127; two test sessions on this Mac (run line above). Session 2 found KI-008 again
  with the new agent: a replaced, unregistered agent was killed on its first start and launchd lost the job; the
  app now unregisters and registers it afresh when it doesn't answer. A fresh reviewer found two important issues
  (a refused agent never reported; a vanished one still shown as running), both fixed test-first.

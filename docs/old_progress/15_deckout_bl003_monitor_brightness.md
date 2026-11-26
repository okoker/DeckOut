# 15 — DeckOut BL-003: monitor brightness moves from where the monitor really is (20/11/2026)

Moved out of `PROGRESS.md` on 26/11/2026.

### 20/11/2026 — Monitor brightness moves from where the monitor really is, never jumping to 5 %
- **Reference:** `docs/REQUIREMENTS.md` (External Monitor Brightness), `docs/reference/app.md` (Settings: m1ddc),
  `Vendor/m1ddc/README.md`; T-170–T-173; BL-003.
- **For a person:** the first brightness turn after the agent started, or after 30 s idle, could take a monitor at
  100 % to 5 %. m1ddc read the monitor's reply 10 ms after asking (DDC/CI wants 40) and printed whatever was in the
  buffer: an empty or shifted reply came out as `0`. It now waits 50 ms, takes only a valid reply and asks again;
  the agent reads each monitor on the first turn instead of trusting a start-up reading, and a monitor that gives no
  reading is left alone with "Left: Monitor Error" on screen. Start-up no longer reads the monitors (31 ms, was ~0.4 s).
- **Decision (owner, 20/11/2026):** leave a monitor with no reading alone, saying "Monitor Error" (it covers cases not
  seen yet); patch DeckOut's own m1ddc and ship it in the app; offer the patch upstream afterwards. (CL calls:) a
  reading outside 0–100 counts as none; the HUD shrinks text that wouldn't fit its box, and centres it.
- **Checked:** run line above. Upstream 1.3.2 reads the same way (waydabber/m1ddc#37 notes it); the patch follows
  ddcutil's and MonitorControl's 50 ms wait and reply checks (read at source). A fresh reviewer: no bugs; T-172's
  idle window widened (it could flake under load). Left as is: Switch Monitor pressed within ~50 ms of a turn can
  read the monitor before the turn's write lands (as before), so the next turn starts one step off.

Run line:
20/11/2026 — BL-003 on `deckout-7-uat-fixes` (ae9ee09): `swift test` 221/221 (new T-170–T-173), watched; T-170, T-171, T-173 failed first against the old code (a 0 read at start-up became 5 %, a failed read 55 %, the message measured 940 pt for 660); m1ddc on both LG monitors, 100 back-to-back reads each: stock 87 of 200 wrong (exit 0), patched 0 wrong, 0 failed; `make install-dev` (build 261120.111028), one `--snapshot` run: KI-008 on the restart, registered again, window "Deck controller running", the agent found both monitors without reading them ("Monitors ready in 31 ms", was 311–520) and drew 14 of 14 and 6 of 6. Not checked: a knob turn and the HUD on screen (owner).

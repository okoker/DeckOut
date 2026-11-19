# Tests

A catalogue: what each test is and what it holds down. Run the suite with `swift test`; it reports its own state.

## Unit — `Tests/DeckCoreTests` (Swift Testing, library `DeckCore`)
| ID | Test | Holds down |
|----|------|------------|
| T-001 | `LegacyTests/n3ParserMatchesToday` | N3 input decoding as in v1.0.0: LCD key, side button, big-knob turn, small-knob turn and press; a non-ACK report and a short report decode to nothing |
| T-002 | `LegacyTests/oldConfigParses` | A v1.0.0-format config (`config.example.json`) still loads: brightness 50, 9 buttons, 3 knobs, 2 displays |

## On the device
Manual checks with the owner; each task's device check is recorded as a run line in `PROGRESS.md`.

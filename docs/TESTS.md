# Tests

A catalogue: what each test is and what it holds down. Run the suite with `swift test`; it reports its own state.

## Unit — `Tests/DeckCoreTests` (Swift Testing, library `DeckCore`)
| ID | Test | Holds down |
|----|------|------------|
| T-001 | `LegacyTests/n3ParserMatchesToday` | N3 input decoding as in v1.0.0: LCD key, side button, big-knob turn, small-knob turn and press; a non-ACK report and a short report decode to nothing |
| T-002 | `LegacyTests/oldConfigParses` | A v1.0.0-format config (`config.example.json`) still loads: brightness 50, 9 buttons, 3 knobs, 2 displays |
| T-003 | `DeckModelTests/modelsMatchOnlyTheTwoDecks` | HID isolation: exactly two models, N3 `0x5548:0x1001` and N4 `0x6602:0x1001`, both on vendor usage page `0xFFA0` usage 1 |
| T-004 | `DeckModelTests/n3Table` | Every N3 key, side button, knob turn and knob press/release decodes to its config key; N4-only codes decode to nothing on the N3 |
| T-005 | `DeckModelTests/n4Table` | Every N4 key (press/release), knob turn (sign), knob press, strip tap and swipe decodes to its config key; `0x38` is not a swipe; N3-only codes decode to nothing on the N4 |
| T-006 | `DeckModelTests/overlappingCodesDecodePerDeck` | A code both decks use (`0x50`, `0x33`, `0x06`) means each deck's own control — one deck can't fire the other's action |
| T-007 | `DeckModelTests/malformedReportsDecodeToNothing` | Non-ACK, short and empty reports decode to nothing on both models |
| T-008 | `DeckModelTests/slots` | Config key → image slot: N4 top row 11–15, bottom row 6–10, strip 1–4; N3 `lcd_1`–`lcd_6` → 1–6, side buttons have none |

## On the device
Manual checks with the owner; each task's device check is recorded as a run line in `PROGRESS.md`.

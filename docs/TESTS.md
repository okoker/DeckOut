# Tests

A catalogue: what each test is and what it holds down. Run the suite with `swift test`; it reports its own state.

## Unit — `Tests/DeckCoreTests` (Swift Testing, library `DeckCore`)
| ID | Test | Holds down |
|----|------|------------|
| T-001 | `LegacyTests/n3ParserMatchesToday` | N3 input decoding as in v1.0.0: LCD key, side button, big-knob turn, small-knob turn and press; a non-ACK report and a short report decode to nothing |
| T-002 | `LegacyTests/oldConfigParses` | v1.0.0's `config.example.json` (frozen in `Fixtures/config-v1.0.0.json`) still loads as the N3 section: brightness 50, 9 buttons, 3 knobs, 2 displays, no N4 |
| T-003 | `DeckModelTests/modelsMatchOnlyTheTwoDecks` | HID isolation: exactly two models, N3 `0x5548:0x1001` and N4 `0x6602:0x1001`, both on vendor usage page `0xFFA0` usage 1 |
| T-004 | `DeckModelTests/n3Table` | Every N3 key, side button, knob turn and knob press/release decodes to its config key; N4-only codes decode to nothing on the N3 |
| T-005 | `DeckModelTests/n4Table` | Every N4 key (press/release), knob turn (sign), knob press, strip tap and swipe decodes to its config key; `0x38` is not a swipe; N3-only codes decode to nothing on the N4 |
| T-006 | `DeckModelTests/overlappingCodesDecodePerDeck` | A code both decks use (`0x50`, `0x33`, `0x06`) means each deck's own control — one deck can't fire the other's action |
| T-007 | `DeckModelTests/malformedReportsDecodeToNothing` | Non-ACK, short and empty reports decode to nothing on both models |
| T-008 | `DeckModelTests/slots` | Config key → image slot: N4 top row 11–15, bottom row 6–10, strip 1–4; N3 `lcd_1`–`lcd_6` → 1–6, side buttons have none |
| T-009 | `ConfigTests/newFormatParses` | Every field of the `decks` format reaches the code under its JSON name (`arrow_ms`, `timeout_s`, `lock_photo` set to non-default values) |
| T-010 | `ConfigTests/defaultsApply` | An `internet` block with no settings gets host `one.one.one.one`, arrow 2 ms, timeout 3 s; an N4 section may omit keys, knobs, strip, swipe, lock photo |
| T-011 | `ConfigTests/unknownBlockTypeThrows` | A misspelt strip block type rejects the file (on reload: previous config kept) instead of silently drawing something else |
| T-012 | `ConfigTests/decksWinsOverTopLevel` | With `decks` present, a top-level N3 layout is ignored — even when `decks` has no `n3` |
| T-013 | `ConfigTests/fileWithNeitherFormatThrows` | `{}` or an incomplete v1.0.0 layout is rejected, not loaded as an empty layout that blanks the deck |
| T-014 | `ConfigTests/exampleConfigParses` | The shipped `config.example.json` is a valid new-format config with both decks |
| T-015 | `ActionResolverTests/n3KeyDownResolvesItsAction` | A key press runs the action configured for that key |
| T-016 | `ActionResolverTests/eachDeckReadsOnlyItsOwnSection` | A control name is looked up only in its own deck's section (no `key_1` on the N3, no `big` on the N4) |
| T-017 | `ActionResolverTests/knobTurnScalesStepBySign` | A knob turn's step is the configured `step` (default 1) times the turn's direction |
| T-018 | `ActionResolverTests/knobDownResolvesPressAction` | A knob press runs the knob's `press` action |
| T-019 | `ActionResolverTests/stripTapAndSwipeResolve` | A strip tap runs its block's action (none if the block has none); a swipe runs `swipe.action`, on the N4 only |
| T-020 | `ActionResolverTests/releasesNoneAndUnsetResolveToNothing` | Key and knob releases, `none` and unconfigured controls run nothing |
| T-021 | `ActionResolverTests/lockedBlocksKeysTapsAndSwipe` | While locked, keys, strip taps and swipes run nothing — even a built-in action |
| T-022 | `ActionResolverTests/lockedKnobsRunOnlyBuiltIns` | While locked, knobs run only the six volume/brightness built-ins; `shell:` and `key:` never run |
| T-023 | `ActionResolverTests/unlockedAllowsEverything` | Unlocked, every input may run every action |
| T-024 | `RenderTests/batHeaderCarriesWireSlotAndLength` | The `BAT` header carries the image length and the wire slot byte as-is (N3 `lcd_1` stays slot 1) |
| T-025 | `RenderTests/n4IconIs112SquareAndTurned180` | N4 key images are 112×112, turned 180° (else upside down on the deck), with a black 4 px margin |
| T-026 | `RenderTests/n4IconKeepsProportions` | A non-square icon is fitted, not stretched |
| T-027 | `RenderTests/n4IconMissingFileIsNil` | A missing icon file gives no image (the caller draws black) |
| T-028 | `RenderTests/stripBlankIsBlackAtSize` | A blank strip block is a black 176×112 JPEG |
| T-029 | `RenderTests/stripPictureIs176x112AndTurned180` | A `picture` block is 176×112 and turned 180° |
| T-030 | `RenderTests/stripPictureMissingFileIsNil` | A missing picture gives no image (the caller draws black) |
| T-031 | `LayoutPlanTests/n4PlanCoversAll14Slots` | A redraw covers exactly the N4's 14 image slots (1–4, 6–15) — none left stale, none invented |
| T-032 | `LayoutPlanTests/n3PlanCoversSixSlots` | A redraw covers exactly the N3's 6 LCD slots |
| T-033 | `LayoutPlanTests/keysShowTheirIconOrBlank` | A key shows its icon; a key with no icon, or not configured, is drawn black (in place, no clear) |
| T-034 | `LayoutPlanTests/stripBlocksMapToTheirContent` | Live types stay live; `picture` shows its icon; `empty` and `picture` without an icon are black |
| T-035 | `LayoutPlanTests/deckWithoutSectionIsAllBlank` | A connected deck with no config section is drawn all black |
| T-036 | `LayoutPlanTests/rendererFallsBackToBlank` | A missing icon or picture still yields a black image of the slot's size, so every other slot draws |
| T-037 | `LayoutPlanTests/n3IconsUseTheN3Pipeline` | N3 icons keep the v1.0.0 85×85 rendering; N4 keys render at 112×112 |
| T-038 | `StripRendererTests/volumeRendersAllStates` | The volume block renders at 0 %, 45 %, 100 %, muted and with no output device; muted looks different |
| T-039 | `StripRendererTests/volumeGaugeFillFollowsPercent` | The gauge arc fills with the level: lit past halfway at 100 %, unlit at 0 % |
| T-040 | `SystemLoadTests/cpuPercentFromTickDeltas` | CPU % = (Δuser + Δsystem) / Δall ticks, with nice counted in the total only |
| T-041 | `SystemLoadTests/cpuPercentNilWithoutElapsedTicks` | No elapsed ticks gives no figure ("–"), not a division by zero |
| T-042 | `SystemLoadTests/cpuPercentSurvivesCounterWrap` | A 32-bit tick counter wrapping between readings still gives the right % |
| T-043 | `SystemLoadTests/cpuColourBoundaries` | CPU colour: green below 50, amber 50–79, red from 80 |
| T-044 | `SystemLoadTests/memoryColourFollowsPressureLevel` | Memory colour follows macOS's pressure level (1/2/4 → green/amber/red), not the % |
| T-045 | `SystemLoadTests/systemReadingsWorkOnThisMac` | The host call and both sysctl names really read on this Mac (a typo would show "–" forever) |
| T-046 | `SystemLoadTests/loadRendersWithMissingFigures` | The load block renders with either or both figures missing |
| T-047 | `LatencyProbeTests/trendFollowsThreshold` | The arrow shows only for a change of at least `arrow_ms` (rise ▲, fall ▼); none on the first reading |
| T-048 | `LatencyProbeTests/echoRequestLayoutAndChecksum` | The echo request bytes, checked against a hand-computed checksum |
| T-049 | `LatencyProbeTests/echoRequestChecksumFoldsToAllOnes` | The checksum is valid for any identifier and sequence |
| T-050 | `LatencyProbeTests/replyMatchesWithOrWithoutIPHeader` | Our echo reply is recognised whether or not macOS includes the IPv4 header |
| T-051 | `LatencyProbeTests/replyForSomeoneElseDoesNotMatch` | Replies to other identifiers or sequences, requests, and truncated packets are ignored (every ICMP socket sees every reply) |
| T-052 | `LatencyProbeTests/internetRendersAllStates` | The internet block renders rising, falling, steady, no reading yet, and no reply |
| T-053 | `LatencyProbeTests/failedBlockIsRed` | No reply turns the whole block red; a normal reading keeps a black background |

## On the device
Manual checks with the owner; each task's device check is recorded as a run line in `PROGRESS.md`.

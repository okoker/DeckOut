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
| T-054 | `LockTests/startsFromTheSessionState` | At start the lock state is the session's own |
| T-055 | `LockTests/recheckCorrectsState` | A "locked" notification the session contradicts is corrected on the next recheck; a real lock with no notification is caught by the recheck; no duplicate callbacks |
| T-056 | `LockTests/slicesCoverRects` | Wide, tall and exact-size photos give one slice per N4 slot, each its rectangle's size |
| T-057 | `LockTests/quadrantsLandInTheRightSlices` | The photo's top-left reaches the top-left key, its bottom-right the rightmost strip block |
| T-058 | `LockTests/slicesAreTurned180` | Each slice is turned 180° (else the photo shows upside down per tile) |
| T-059 | `LockTests/n4RectsMatchTheMeasuredLayout` | The lock photo's slot rectangles match the layout measured on the N4 (keys 172 apart, rows 176, strip 352 below, blocks 208 apart) and fit the 800×464 face |
| T-060 | `ConfigTests/internetNumbersOutOfRangeAreRefused` | An internet block's `timeout_s` outside 0.1–60 or a negative `arrow_ms` makes the config invalid (else the daemon crashes at the first measurement and launchd restarts it into the same crash) |
| T-061 | `ReloadTests/burstOfRequestsReloadsOnce` | Twenty reload requests in a burst run one reload, and every requester gets its result (a slider drag in the app must not redraw the decks dozens of times) |
| T-062 | `ReloadTests/brightnessIsRebuiltOnlyWhenDisplaysChange` | The monitor control (which runs `m1ddc` and can stall) is rebuilt on reload only when `displays` changes, order included; no displays and an empty list are the same |
| T-063 | `ConfigTests/roundTripKeepsEveryField` | A config with every field set, two presets per deck, steps and an internet block reads back equal after encoding (the app rewrites the file on every change) |
| T-064 | `ConfigTests/oldFilesReadAsOneDefaultPreset` | The v1.0.0 file and a `decks` file without `presets` each read as one preset "Default", live, with all their keys |
| T-065 | `ConfigTests/activePresetPicksKeysAndStrip` | The live preset's keys and strip are what the deck shows and runs |
| T-066 | `ConfigTests/unknownActivePresetFallsBackToFirst` | An `active_preset` that names no preset falls back to the first preset, never blank keys |
| T-067 | `ConfigTests/duplicateOrEmptyPresetNamesAreRefused` | Two presets with one name, an empty name, or no presets make the file invalid (the live preset is picked by name) |
| T-068 | `ConfigTests/encodedFileUsesTheDecksFormat` | Writing an old file gives the `decks` form with presets and no top-level `buttons` / `brightness`; non-internet blocks don't carry the internet settings |
| T-069 | `ConfigFileTests/saveWritesAtomicallyWithMode600` (+ `saveCreatesAMissingFolderPrivately`) | A save leaves the file at mode 0600, passing the load-time checks and reading back equal, with no temp file left; a missing folder is created at 0700 |
| T-070 | `ConfigFileTests/firstSaveKeepsABackupOnce` | The first save over an existing file keeps it as `config.json.before-app` (0600); later saves never overwrite that backup; no file, no backup |
| T-071 | `ConfigFileTests/securityProblemsAreReported` | A symlink, a world-writable file and a missing file are each refused with a reason; a 0600 file passes |
| T-072 | `ConfigFileTests/startupWithoutAUsableConfigRunsBlank` | A missing, unparseable or world-writable config at start gives no decks set up and a reason, never an exit (launchd would crash-loop) |
| T-073 | `ConfigFileTests/resolvePathPrefersFlagThenExistingThenDefault` | `--config` wins; then the first existing of `~/.config/vsd/config.json` and the executable's folder; neither gives the home path; `--config` alone is an error |
| T-074 | `ConfigTests/lockPhotoReadsStringOrObject` | `lock_photo` reads as a path (zoom 1, centred) or as the framing object; zoom 0.5 or 11 makes the file invalid |
| T-075 | `LockTests/framingZoomsAndMovesThePhoto` | Placement on the 800×464 face: aspect-fill, zoom about the centre, positive `offset_y` moves the photo down |
| T-076 | `LockTests/framingNeverLeavesBlackEdges` | Tall and wide photos at any offset (±1, ±10) and zoom 1 or 3 still cover the whole face |
| T-077 | `ProcessRunnerTests/capturesOutputAndExitStatus` | A command's stdout, stderr and exit status come back separately; 200 KB of output is capped at 64 KB with a truncation mark |
| T-078 | `ProcessRunnerTests/timeoutAndMissingExecutableReportErrors` | A command past its timeout is stopped and reported as timed out within a second or two; a missing program reports an error and no exit status |
| T-079 | `ShellEnvironmentTests/readsTheEnvironmentBetweenMarkers` | The environment is read from between the markers, whatever the startup files print before it |
| T-080 | `ShellEnvironmentTests/fallsBackOnHangInputOrNoMarkers` | A shell that hangs, reads input or prints no markers falls back within 3 s with a reason, and Homebrew's folders on PATH |
| T-081 | `ShellEnvironmentTests/fallbackAddsHomebrewPaths` | The fallback PATH adds `/opt/homebrew/bin` and `/usr/local/bin` once each, after the existing entries |
| T-082 | `ActionKindTests/parsesEveryKind` | Every action string maps to its kind; a `url:` keeps its path, query and fragment |
| T-083 | `ActionKindTests/badPayloadsAreInvalid` | `app:` without a path or `.app`, non-http(s) or malformed `url:`, relative `open:`, empty `script:` / `shortcut:` and unknown actions are invalid, with a reason |
| T-084 | `ActionResolverTests/pressesCarryTheirStep` | A key, knob press, strip tap and swipe pass their own signed `step` (else a volume key does nothing); a key without one passes none |
| T-085 | `ActionResolverTests/newKindsNeverRunWhileLocked` | `app:`, `url:`, `open:`, `script:`, `shortcut:` and the media keys never run from a key, knob press or strip tap while locked; all run unlocked |
| T-086 | `ActionDispatcherTests/scriptRunsAsGivenWithTheEnvironment` | A script whose path has spaces, quotes and `$` runs as given (no shell string) with the user's environment, and its output comes back |
| T-087 | `XPCTests/statusAndReloadRoundTrip` | Over a real XPC connection, `status` and `reload` replies decode to what the agent returned |
| T-088 | `XPCTests/testRequestReturnsTheActionResult` | A `test` request reaches the agent unchanged, and its `ActionResult` comes back to the client |
| T-089 | `XPCTests/clientHearsStatusChanges` | A connected client is told the new status when the agent's status changes (decks plugged in or out) |
| T-090 | `XPCTests/badRequestGetsAnError` | A `test` request that doesn't decode gets the error "bad request" and never reaches the agent |
| T-091 | `AgentTests/agentReloadReportsAndClearsTheProblem` | With no config the agent runs blank and reports "No config yet"; a reload that loads clears the problem and shows the live presets; a reload of a broken file keeps the previous config and reports why |
| T-092 | `ActionDispatcherTests/programsDontWaitForEachOther` | A quick command finishes at once while a slow one is still running (a Test run or a slow key never holds up the next press) |
| T-093 | `ReloadTests/outsideReloadRebuildsTheMonitorControl` | A reload from outside rebuilds the monitor control (finds monitors plugged in since start); an app save with the same `displays` reuses it |
| T-094 | `XPCTests/previewEndsWhenItsClientGoes` | When the connection that put up the lock photo preview goes away, the preview is taken down (the N4 doesn't stay on the photo after the app quits) |
| T-095 | `IdentityTests/derivesNamesFromBundleID` | Release and dev DeckOut derive their agent label, plist name, config file and log folder from the bundle id; the dev variant never shares the live config |
| T-096 | `IdentityTests/unknownBundleIsNotDeckOut` | Only the two DeckOut bundle ids count as DeckOut: a hand install (`com.streamdeck.controller`) or no bundle keeps today's behaviour |
| T-097 | `AgentLaunchTests/configPathOrder` | `--config` wins; inside DeckOut the identity's config path (even before it exists); a hand install searches today's candidates |
| T-098 | `AgentLaunchTests/logRollsOverLimit` | The agent's log moves to `.1` at start when over the limit, so it never grows without end across restarts |
| T-099 | `AgentLaunchTests/statusCarriesBuildFromLaunch` | `status` reports the version and build read at launch (a new app copied over the bundle doesn't change them); an older agent's status without `build` still decodes |
| T-100 | `CodeSigningTests/requirementForms` | The requirement strings: team id + identifier when signed, identifier + code hash when ad hoc, none (refuse) otherwise; nothing with a quote or non-hex gets into one; what the app asks of the agent |
| T-101 | `CodeSigningTests/cdhashPinsOneBinary`, `readsOwnSignature` | A code-hash requirement passes for the exact binary and fails for any other hash (on `/bin/ls`); the running process can read its own identifier and hash |
| T-102 | `XPCTests/refusesAPeerThatDoesNotMatch` | A process that isn't our app is refused before any call runs (a `key:` test never reaches the agent); no requirement means every connection is refused. Fails if `setCodeSigningRequirement` is removed |
| T-103 | `XPCTests/acceptsAPeerThatMatches` | A peer that meets the requirement gets its replies |
| T-104 | `XPCTests/restartRepliesThenExits`, `AgentTests/restartExitsAfterTheReply` | `restart` replies first and exits only afterwards (0.3 s), so the app hears the answer before KeepAlive starts the new binary |
| T-105 | `XPCTests/liveStripPushedToClients` | The live strip's images reach the app on request and are pushed when a block gets a new one |
| T-106 | `AgentTests/liveImagesKeyedByBlock` | A live image goes to every block of its type in the live preset; switching preset drops blocks that aren't live there |
| T-107 | `scripts/check-bundle.sh` (build check, run by `make app`) | An assembled DeckOut.app: Info.plist (bundle id, executable, macOS 15, build), the agent plist (label = Mach service = `--mach-service` argument, `BundleProgram`, KeepAlive), the helper signed as the agent label and the app as its bundle id, a strict signature check, arm64 only, nothing loose in the bundle root |
| T-108 | `RegistrarTests/registersWhenNotRegistered` | The app registers its agent when macOS has none, leaves an enabled one alone, and, when it doesn't answer, unregisters and registers it afresh (KI-008: a stale job after a launch constraint violation) |
| T-109 | `RegistrarTests/notFoundUnregistersThenRetries` | macOS reporting "not found" (after a Login Items reset, or just after install): unregister once, register, retry up to 10 × 1 s; still not found → a failure with a message |
| T-110 | `RegistrarTests/requiresApprovalIsReported` | Switched off in Login Items → "needs approval", also when `register()` is refused for that reason; any other refusal passes its message on |
| T-111 | `AgentLinkTests/restartsAnOlderAgentOnce` | An agent of another build (or one too old to report it) is asked to restart once; if the same build comes back, the app says so and doesn't loop |
| T-112 | `AgentLinkTests/hearsStatusAndStrip`, `silentAgentIsReportedOnce`, `refusedLinkIsReportedAndBacksOff`, `droppedAgentIsNotShownAsRunning` | The app's link hears status and live strip pushes and reconnects when the agent goes away. An agent that doesn't answer, whether silent or refusing every connection at once, is reported once (the app registers it afresh, then starts over on a new connection), and retries back off instead of hammering it. A dropped agent's last status is forgotten after a short grace, so the window doesn't keep drawing decks from it |
| T-113 | `AppLocationTests/onlyFromApplications` | DeckOut runs only as `/Applications/DeckOut.app`: Downloads, a translocated copy, a subfolder, a renamed copy or a disk image are refused (the agent would point at a folder that goes away); the dev variant runs anywhere |
| T-114 | `DeckFaceTests/n4MatchesMeasuredRects` | The app's N4 drawing puts every key and strip block at half its measured position (`LockPhoto.n4Rects`), inside the deck, with a person's name for each control |
| T-115 | `DeckFaceTests/everyConfigKeyOnce` | Each deck's drawing has every config key exactly once (N3: 6 keys, 3 buttons, 3 knobs; N4: 10 keys, 4 strip blocks, 4 knobs) and no two controls overlap |
| T-116 | `DeckFaceTests/previewIsUpright` | Key and picture previews come out upright at the deck's sizes (the deck's own copies are turned), and a live block's JPEG as drawn on the deck is turned back upright |
| T-117 | `DeckViewTests/drawsImagesAndRing` | The deck drawing shows a key's image on its screen, a red ring around the selected control only, and an empty screen as empty; writes light / dark PNGs of both decks to the temp folder for a look |
| T-118 | `AppModelTests/screenFollowsTheDecks`, `screenBeforeTheDecks`, `ScreenSnapshotTests/writesEveryScreen` | The window's screen: not in Applications → move it; not registered yet → starting; switched off in Login Items → allow it; failed or not answering → the problem with Try Again; then the decks: none → plug in, one → it, both → pick, the shown deck stays while plugged in and gives way to the other (or plug in) when unplugged, never a deck that isn't there. The status line says "Reconnecting" (amber) while the link is down (`AgentLinkTests/statusLineFollowsTheLink`). Every screen renders (PNGs for a look) |
| T-119 | `ConfigFileTests/saveRefusesWhatDoesNotRoundTrip` | A config that wouldn't load back (e.g. a lock photo zoom outside 1…10) is never written; the file stays as it was |
| T-120 | `ConfigStoreTests/changeSavesAndReloads`, `PresetTests/sliderDragIsOneUndo`, `EditorSnapshotTests/brightnessDoesNotRedrawKeys` | Each change in the app is saved whole (mode 0600) and asks the agent to reload once; a change that changes nothing saves nothing; a slider dragged through 30 values leaves the last one on disk, and a whole drag is one undo step; a drag (or an action change) doesn't decode every key icon again |
| T-121 | `ConfigStoreTests/undoRestoresTheWholeConfig`, `undoKeepsAHandEdit` | Undo puts back the whole config from before a change (a renamed and deleted preset come back, the live preset too), saved and reloaded; redo; a new change drops the redo. A hand edit picked up since starts the history again (with a notice), so undo never throws it away |
| T-122 | `ConfigStoreTests/handEditIsPickedUp`, `aFixedProblemUnblocksEdits`, `EditorSnapshotTests/anEditKeepsAHandEditedIcon` | A hand edit made while the app is open is kept: the next change builds on it. A hand edit that doesn't load is never saved over, the app says why, and changes work again once it loads, including after a fix that leaves the bytes alone (chmod 600). A failed save is shown and doesn't block the next try. An edit in the app keeps a hand-edited icon |
| T-123 | `AgentTests/appReloadLogsOneLine` | A reload the app asks for logs one line ("Config reloaded (from the app): N4 Work"), not the whole config, so the log doesn't grow by a config per edit |
| T-124 | `XPCTests/accessibilityRequestReachesTheAgent` | The app's "Allow…" reaches the agent (which asks macOS to list it under Accessibility) and hears whether it's allowed |
| T-125 | `ActionChoiceTests/roundTripsEveryKind`, `menusFitTheControl`, `actionCheckSaysWhatsWrong` | Every action the app offers reads back from the config as what was picked (today's hand-written strings too); knob turns offer only volume and monitor brightness; ZR7 is on no menu; volume and brightness show as Up / Down on keys; the app shows the agent's own reason a string wouldn't run |
| T-126 | `KeyNamesTests/recordsWhatTheDispatcherCanPost` | The shortcut recorder writes `cmd+shift+4`-style strings from one key table shared with the agent; a key the agent can't post (outside the table) is refused, so no shortcut is saved that silently does nothing |
| T-127 | `IconFilesTests/appIconAndCopiedImageLandInIcons` | An app's own icon is rendered to a 256 px PNG in the config's `icons/` folder (folder 0700, files 0600 from creation), the same file for the same app; a chosen picture is decoded and saved as a PNG at most 512 px on a side (the deck refuses over 1024), so moving the original changes nothing; a file that isn't a picture is refused |
| T-128 | `IconFilesTests/editsReachTheLivePreset` | An edit lands in the live preset only (keys, buttons, strip blocks) or on the deck (knobs); a deck with no section gets one ("Default", brightness 75) on its first edit |
| T-129 | `EditorSnapshotTests/editorsDraw`, `knobAndStripEditorsDraw` | The key, knob and strip-block editors draw in a real offscreen window for each kind of action, light and dark (PNGs for a look); a key whose script is gone is the only one marked |
| T-130 | `MissingFilesTests/findsWhatIsGone` | Keys, knob presses and strip taps whose app, file, folder, script, icon or picture is gone are found (and marked on the drawing); ones whose files are there aren't |
| T-131 | `MissingFilesTests/scriptWarnings` | A script that isn't there or isn't executable is told apart; "Make Executable" adds only the owner's execute bit; a script or file in Desktop, Documents, Downloads or iCloud Drive gets a note that macOS will ask (by path; nothing there is read) |
| T-132 | `PresetTests/presetOperations` | Presets from the toolbar: switch, New ("Preset N", blank, live), Duplicate ("Work copy", "copy 2", live), Rename (never empty or taken; stays live); a deck with no section gets one; brightness 0–100 per deck |
| T-133 | `PresetTests/deleteLiveFallsBackAndUndoes` | The last preset can't be deleted; deleting the live one makes the first left live; undo brings it back, live again, on disk |
| T-134 | `LockTests/panelIsWhatSlicesCut` | The app's drawing of the lock photo (the framed panel) is exactly what the deck's slices cut, each slice its rectangle turned 180° |
| T-135 | `LockTests/offsetsClampToTheEdge` | The photo's offsets have limits at each zoom; clamped to them, the photo sits where it did, so a drag past the edge and back moves it at once (no dead zone); zoom stays 1–10 |
| T-136 | `LockTests/previewDecodesOnce` | While the app's preview is up, the agent decodes the photo once, not per framing sent during a drag |
| T-137 | `LockPhotoModeTests/choosingCopiesAndChecks` | A chosen lock photo is copied into the config folder (`lock-photo-<hash>`, 0600) and starts centred at zoom 1; a file that isn't a picture is refused with a message and the config keeps its photo |
| T-138 | `LockPhotoModeTests/framingIsClampedAndUndoable` | Moving the photo is clamped at its edge and a whole drag is one undo step; zoom stays 1–10; Reset centres it; Remove takes it off and undo brings it back |

## On the device
Manual checks with the owner; each task's device check is recorded as a run line in `PROGRESS.md`.

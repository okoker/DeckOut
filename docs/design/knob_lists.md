# Knob Lists and Per-Preset Knobs — Design

**✅ BUILT 26/11/2026 → `docs/reference/n4.md` (Knob lists), `docs/reference/app.md` (Editing: Knob lists).** This
design stays as the record of why.
Approved by the owner 26/11/2026; builder-checked the same day.
Current behaviour this changes: `docs/REQUIREMENTS.md` (Configuration, Actions), `docs/reference/n4.md`,
`docs/reference/app.md` (Editing).

## Intent
The owner wants a knob on the N4 that picks from a short list: a few websites or apps. Turning the knob steps through
the list, and the strip block directly above that knob shows the current pick's icon. Pressing the knob, or tapping
that block, opens the pick. It gives more launch targets than the ten keys, in a spot the hand already finds.

The strip belongs to a preset, but today the knobs belong to the whole deck. A swipe changes the strip, so a knob
tied to one block would show stale picks or block that spot in every preset. The owner's answer: **knobs become part
of each preset**, like keys and strip blocks. The owner and a few friends use DeckOut; it is public on GitHub.

## Goals
1. **Knobs per preset**, on both decks. Each preset has its own knobs; a swipe to another preset brings that preset's
   knobs with it.
2. **No visible change on upgrade.** An existing config's knobs are copied into every preset, so the decks behave
   exactly as before until the owner changes something.
3. **Knob lists** on the N4: a knob's turn can be "Pick from a list". The list holds items, each an action (anything
   a key can do: website, app, file, Shortcut, command…) with its own icon. The strip block above the knob shows the
   pick's icon; a press of the knob or a tap of the block runs the pick.
4. **Set up in the app**, in one place (the knob), with undo, as every other control is.

## Non-goals
- **Fetching a website's icon** automatically: icons are chosen by hand, as for keys today (owner, 26/11/2026).
  Deferred as BL-041.
- **Lists on the N3**: it has no screen above its knobs. Its knobs still become per preset.
- Lists on keys or strip blocks alone; a list's name or a position marker ("3 of 5") on the block; remembering the
  pick across a restart of the agent.
- A deck-wide knob default with per-preset overrides (see Approaches).

## Anti-goals (a failure even if everything "works")
- The upgrade changes what any knob does, or leaves a knob dead.
- A list disappears without an error: dropped by a save (the app's or the agent's), or by a hand edit the app
  rewrites. (A save by 2.1.0 after going back is the accepted exception: see The file.)
- Turning the knob feels sticky: the block lags behind an ordinary turn.
- The window shows a knob doing one thing while it does another.
- Anything from a list runs while the Mac is locked.

## Approaches
**Where the knobs live** (owner, 26/11/2026):
- **Each preset owns all its knobs (picked).** Plain and visible: what a knob does is in the preset, nowhere else.
  The cost is repetition: changing the volume step means changing it in each preset.
- A deck-wide default that a preset may override (turned down). Set volume once, but every knob has two possible
  sources, and editing the default while a preset overrides it changes nothing on the deck, with no error saying why.

**Where the list lives** (owner, 26/11/2026):
- **A. The knob owns the list; the block above only shows it (picked).** Set up in one place, nothing to keep in step.
- B. The block owns the list and the knob gets two new actions ("step the block above", "open its pick") (turned
  down). Two settings must agree; a list block above a knob left on volume shows a site, scrolls nothing, and gives
  no error.
- A list block quietly taking over the knob below it (dropped): the window would say volume while the knob scrolls.

**Website icons** (owner, 26/11/2026): chosen by hand now (B); DeckOut fetching them is BL-041. A favicon service is
ruled out: it would learn the list of sites.

## Decided by the owner (26/11/2026)
- Knobs are per preset, on both decks. An existing file's knobs go into every preset.
- **New Preset** on the N4 starts from a fixed baseline (owner, after the deck check): knob 2 monitor brightness /
  switch monitor, knob 4 volume / mute, block 1 latency (no tap), block 2 CPU / memory (tap: Activity Monitor), block 4
  volume (owner, after the 2.2.0 release), the rest empty; an N4's first preset starts the same way, and an existing file is never changed. Not a copy of the live
  preset's built-in knob halves, which would carry a knob set for one preset into every new one (like the sample's
  knob 1 on volume, read as interference); and nothing personal (ZR7, a script), which lives in the person's file. The N3
  keeps the built-ins copy (`LockPolicy.builtIns`). **Duplicate** copies everything, lists included (as now).
- The list is on the knob (A). A list item is anything a key can do, with its own icon.
- Icons are picked by hand. For the test the builder picks 5 random websites and fetches their icons by hand.
- Going back to 2.1.0 with an N4-only file loses its knobs; accepted, the rollback copy is the way back (The file).
- While a list is edited, the deck keeps its own pick; it doesn't follow the editor's selected row (The app).

## The file
Knobs move from the deck section into each preset. A knob is either a turn and a press, as now, or a list.
```json
"n4": {
  "brightness": 50,
  "swipe": { "action": "next_preset" },
  "presets": [
    { "name": "Work",
      "keys":  { "key_1": { "action": "shell:open -a Notes", "icon": "…" } },
      "strip": { "2": { "type": "load" } },
      "knobs": {
        "knob_1": { "list": [
          { "action": "url:https://en.wikipedia.org", "icon": "/Users/…/.deckout/icons/image-….png" },
          { "action": "app:/Applications/Safari.app", "icon": "/Users/…/.deckout/icons/app-….png" }
        ] },
        "knob_4": { "rotate": { "action": "system_volume", "step": 5 }, "press": { "action": "system_mute_toggle" } }
      } }
  ],
  "active_preset": "Work"
}
```
- **List items** have the fields of a key (`ButtonConfig`): `action`, optional `icon`, `step`, `tile`. An empty list
  is valid (the app saves after every change, so a list starts empty).
- **Reading an older file:** a preset with no `knobs` key gets a copy of the deck section's `knobs`, if it has any. A
  preset with its own `knobs` (even `{}`) keeps them. The N3's deck-level `knobs`, required today, becomes optional.
- **Writing:** `knobs` is written in every preset and never at deck level. Every save (the app's, and the agent's
  `next_preset` save) writes the new form.
- **Refused at load** (the file is invalid, as an unknown block type is today): a knob with both `list` and
  `rotate`/`press`; a knob with neither; a list on an N3 knob.
- **The linked block** is fixed by position: `knob_1` ↔ strip block `"1"` … `knob_4` ↔ `"4"` (measured left to
  right, `docs/reference/n4.md`). While a knob has a list, the block's own config in that preset is set aside: the
  app clears it when the list is made; in a hand edit that has both, the list wins and the agent logs one line saying
  so.
- **Going back to 2.1.0:** with an N3 section, 2.1.0 refuses the new file (it requires deck-level `knobs`,
  `Config.swift:173`) and loses nothing. With only an N4 section it loads it with every knob dead (its N4 knobs are
  optional at deck level, `Config.swift:232`, and its presets ignore a `knobs` key, `Config.swift:131`), and its
  first save, a swipe's `next_preset` or any app edit, writes the file without the per-preset knobs and lists.
  **Accepted** (owner, 26/11/2026: one other known user): no marker to make 2.1.0 refuse the file. The way back is
  the rollback copy.
- **Rollback copy** (CL call): `ConfigFile.save` keeps a one-time copy of the file as it was before the first save
  by the new version, `config.json.before-2.2` (named after the release that ships this), beside the existing
  `.before-app`. Restoring it rolls back, losing edits made since. The unused-icon cleanup already keeps icons named
  in any file in the config folder, so the copy's icons survive. The release notes say how to roll back.

## The agent
- **Position** (CL call): each list knob's pick is kept in memory per deck, preset and knob, starting at the first
  item. It survives a swipe away and back, and a reload (kept if the list still has that many items, else back to
  the first). It is never written to the file: saving on every click would churn the file and widen the swipe /
  save race of KI-013. A restart starts every list at its first item.
- **Turning** steps one item per click, either way, wrapping from the last item to the first and back (as
  `next_preset` wraps) (CL call). Each click redraws the deck; only the block above changes, so only that slot is
  sent (`ShownSlots`). `LayoutPlan.slots` draws the block as a `picture` of the pick's icon, or black when the pick
  has no icon or the list is empty.
- **Press and tap:** a press of the knob, or a tap on its block, runs the pick's action exactly as a key press would
  (`ResolvedAction(action, step)` through the dispatcher). An empty list does nothing, with a log line.
- **Locked Mac** (CL call): turning, pressing and tapping a list knob do nothing while locked (logged "ignored while
  locked"), whatever the pick's action is. With a lock photo the block is covered anyway; on unlock it shows the pick
  again. Ordinary knobs keep today's rule (built-ins only).
- **Log:** a turn logs the pick, e.g. `Input n4 knobTurn(knob_1, 1) → list 3/5 url:https://…`; the load summary
  lists each preset's knobs.
- Every reader of deck-level knobs moves to the live preset's: `ActionResolver`, `ActionDispatcher` (the load-time
  Accessibility check walks every preset's knobs and list items), `Agent` (load summary).

## The app
UI first: the plan's first step mocks the knob editor in the real window (`--snapshot`, built on the current
`KnobEditor` and `StripEditor`) for the owner to see before the file or agent change.

- **Where edits land:** knobs in the live preset, like keys (`ConfigEdits.setKnob`). The window's knob captions and
  missing-file marks read the live preset's knobs (`AppModel`, `MissingFiles`).
- **Knob editor, N4:** the Turn menu gains "Pick from a list". Chosen, the Press row is replaced by a note ("Press
  the knob, or tap the block above, to open the pick"), and the list appears:
  ```
  Turn   [ Pick from a list      ▾ ]
         ┌──────────────────────────────┐
         │ ▣  en.wikipedia.org          │  ← selected row
         │ ▣  github.com                │
         │ ▣  Safari                    │
         └──────────────────────────────┘
          [+] [−]            [↑] [↓]
  ─────────────────────────────────────
  Item   [ Open Website           ▾ ]      (the key's action menu and fields)
         https://en.wikipedia.org
  Icon   [ App | Image | Text | Library ]  (block-shaped, 176 × 112, as a strip block's)
  Test   [ Test ]
                                  Clear Knob
  ```
  Rows show the item's icon and a short name (the site's host, the app's or file's name, the action's name). `+`
  adds an item after the selected one; `−` removes the selected one; ↑ / ↓ reorder (as Settings → Monitors does).
  Each is one undo step. An item's icon works as a key's: an Open App item shows its app's icon until another is
  chosen; any other item stays black on the deck until an icon is chosen (no generated default, CL call).
- **Making a list** clears the block above in the live preset, in the same undo step. Turning the knob back to
  something else leaves the block blank (⌘Z restores it).
- **The block above, selected in the window:** "Shows knob N's list" in place of its settings, with a button that
  selects the knob (CL call).
- **The block in the window** shows the pick the deck shows, read from the agent as live blocks' images are today
  (`liveStrip`); until the agent says, the first item (CL call; the builder may pick the cheapest way that keeps the
  window and the deck in step).
- **The editor's selected row and the deck's pick are separate** (owner, 26/11/2026). Choosing an icon for item 3
  while the deck shows item 1 changes the editor's preview, not the deck, until the knob is turned to item 3. After a
  reorder or removal the deck's pick keeps its number, so it may show another item. No call from the app tells the
  agent what to show. The mock shows the selected row and the deck's pick as two separate things.
- **Knob caption** on the deck drawing: the list's size, e.g. "List of 5".
- **New Preset** on the N4 starts from the baseline (Decided, above), whatever the live preset holds.
- **BL-035 widens:** text half-typed in a knob or list-item field can commit to the same knob in the preset a swipe
  just made live, because the editor is rebuilt per control, not per preset. Fix it in this build: rebuild the editor
  when the live preset changes (CL call).

## Tests (lean)
- **Config:** a 2.1.0 file (deck-level knobs, N3 and N4) loads with those knobs in every preset and writes them only
  in presets; a preset with its own `knobs: {}` keeps none; a list knob round-trips through the app's save
  unchanged (the silent-drop guard); the three refusals; `.before-2.2` is written once, with the old bytes.
- **Agent:** turns wrap both ways; press and tap run the pick; locked does nothing; the position survives a preset
  switch and back and a reload, and resets when the list shrinks below it; the block draws the pick's icon and only
  that slot is sent.
- **App:** New Preset on the N4 gives the baseline; Duplicate copies a list; making a list clears the block above in one
  undo step.
- **On the deck** (DeckOut Dev session; each step with the owner's go, per the dev-testing routine): knob 1 of the N4
  with 5 random websites, icons fetched by hand into `~/.deckout-dev/icons/`. Turn both ways past the ends, press,
  tap the block, swipe away and back, lock and unlock; the window's block follows the deck. The owner's existing
  knobs work unchanged after the upgrade.

## Docs when built
`REQUIREMENTS.md` (Structure, presets, knobs, Actions), `reference/n4.md` (Config, Input), `reference/app.md`
(Editing, Presets), `TESTS.md`, README if it shows the file. This design gets its ✅ BUILT marker.

## Left to the builder
- How the window learns the deck's pick (extend `liveStrip`, or another call), as long as the two stay in step.
- Whether a fast spin needs its redraws merged; measure on the N4 first.
- The editor's exact controls and spacing, within the mock the owner approves.
- Swift types and names: the list's shape in `KnobConfig`, where the position is kept.

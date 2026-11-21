# Config App + Second Deck

**Promoted → `docs/design/config_app.md`; the second deck → `docs/design/n4_support.md`.** Both built: the app is
DeckOut 2.0.0 (21/11/2026), the N4 is supported.

Idea, noted 02/11/2026. Trigger: the arrival of a second, more capable stream deck.

## What
- Turn the daemon into a macOS app with a UI for assigning buttons and knobs (today: hand-edited `~/.config/vsd/config.json`).
- Support the new deck (model TBD) alongside or instead of the TreasLin N3.

## Leaning
- **Distribution: direct, not the App Store.** The App Store sandbox blocks what makes the tool useful: `shell:` actions (arbitrary commands), spawning `m1ddc` for monitor brightness, and osascript automation of other apps. Direct distribution = Developer ID signed + notarized.
- **Signing waits for the app.** The current ad-hoc binary shows "Item from unidentified developer" in Login Items — accepted until then. A Developer-ID-signed app shows the certificate's name there and keeps macOS permissions across updates (ad-hoc builds lose them on every rebuild).
- Keep signing identity names out of the repo; configure them locally.

## What changes
- `REQUIREMENTS.md` Non-Goals "No GUI" and "No multi-deck support" flip.
- Device-specific (new deck likely needs its own): `Protocol.swift`, `HIDDevice.swift` (CRT packets, init order, keepalive), `ImageLoader.swift` (85x85 JPEG, rotation, LCD offsets).
- Likely reusable: `Config.swift`, `ActionDispatcher.swift`, `VolumeControl.swift`, `BrightnessControl.swift`, `BrightnessHUD.swift`.

## Settings the app must expose
- Deck brightness, per deck, 0–100, default 75 (owner, 19/11/2026). On the N4 the whole range is usable: each step up to 100 is visibly brighter, and 0 is dim, not off.
- Lock photo (owner, 19/11/2026): choose the image, then move and zoom it, with a preview of what each of the N4's 14 screens shows. Today the daemon takes a fixed centre crop, and the frames between keys hide part of the picture (e.g. eyes landing between the two key rows).

## Open questions
- Which deck, and is its protocol documented or does it need reverse-engineering like the N3?
- One app, or a background daemon plus a separate settings app?
- Login item: register the agent from inside the app bundle (`SMAppService`, macOS 13+) instead of a hand-installed LaunchAgent plist?
- Config format: keep the current JSON (so existing configs carry over) or migrate?

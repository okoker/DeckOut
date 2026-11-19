# 03 — CoreAudio volume and early fixes (27/03/2026)

Moved out of `PROGRESS.md` on 19/11/2026.

- Volume control via CoreAudio `kAudioDevicePropertyVolumeScalar` (27/03/2026) — replaced NSEvent media keys, which need Accessibility and break on every reinstall
- Bug fixes (27/03/2026): sendPacket report ID stripping, configKey mapping, CFRunLoop requirement

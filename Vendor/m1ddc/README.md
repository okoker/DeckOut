# m1ddc 1.3.3 (vendored, unchanged)

Source of https://github.com/waydabber/m1ddc tag v1.3.3 (MIT, see LICENSE): the release tarball's sha256
`9e4581dc2b3b6b4b1bcd3c8fca5ca45b6bb217a609349bd352751212c0de21e8`, the one in Homebrew's formula (checked
26/11/2026). Only `sources/`, `headers/` and `LICENSE` are kept, byte for byte; the Makefile builds them with one
clang line, the same flags as upstream's (theirs is not run). Scanned before vendoring: it writes only to stdout; no
network, no processes, no files. `avservice.m` (new in 1.3.2, for `display list all` and `serial=`, which DeckOut
doesn't use) reads the IORegistry and each monitor's EDID over I2C.

## Why 1.3.3 or later

DeckOut reads a monitor's brightness before moving it. Up to 1.3.2, m1ddc read the reply 10 ms after asking (DDC/CI
asks for at least 40) and decoded it unchecked: on an LG HDR 4K pair, 87 of 200 back-to-back reads came back empty,
as an echo of the request or shifted by two bytes, printed as `0` (or 41984) with exit 0, and the agent moved a
monitor at 100 % to 5 % (BL-003). 1.3.3 carries DeckOut's fix (waydabber/m1ddc#81): a read waits 50 ms
(`--read-wait`), only a valid reply is decoded (header, the code asked for, checksum), and an invalid one is asked
for again, up to 4 times; a read that gets none prints `DDC communication failure: …` and exits 1. A display that
answers "unsupported VCP code" gets `Unsupported VCP code 0x..` and exit 1 at once. On the same LG pair, 1.3.3: 200
of 200 reads right, none failed, about 170 ms a read (26/11/2026).

An LG 27UP85NP-W puts `0x51` where the reply's length byte `0x88` belongs, so 1.3.3 rejects all its reads and
DeckOut leaves that monitor alone ("Monitor Error"); the fix is waydabber/m1ddc#83.

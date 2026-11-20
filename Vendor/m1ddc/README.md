# m1ddc 1.3.1 (vendored, patched)

Source of https://github.com/waydabber/m1ddc tag v1.3.1 (MIT, see LICENSE), checked 19/11/2026 against the
sha256 in Homebrew's formula. Only `sources/`, `headers/` and `LICENSE` are kept; the Makefile builds it with one
clang line (theirs is not run). Scanned before vendoring: it writes only to stdout; no network, no processes.

## DeckOut patch (20/11/2026)

Reads (`get`, `max`, `chg`) are patched; writes are as upstream. Every change is marked `DeckOut patch` in
`headers/i2c.h`, `sources/i2c.m` and `sources/m1ddc.m`.

- **Wait 50 ms before reading a reply** (`DDC_READ_WAIT`), not 10 ms. DDC/CI asks the host to wait at least 40 ms;
  ddcutil and MonitorControl wait 50 ms.
- **Decode only a valid reply** (`isValidDDCReply`): 0x6E, 0x88, opcode 0x02, result 0x00, the VCP code asked for,
  and a correct checksum (0x50 XOR bytes 0–9). Upstream decodes whatever is in the buffer.
- **Ask again** when the reply isn't valid or the I2C call fails: up to 4 times, 50 ms apart. If none is valid it
  prints `DDC communication failure: no valid reply` (or the I2C error) and exits 1, as a failed read already did.

Why: on an LG HDR 4K pair the stock 1.3.1 read comes back empty, as an echo of the request, or shifted by two bytes,
and is printed as `0` (or 41984) with exit 0: 87 of 200 back-to-back reads of two monitors at 100 % were wrong
(20/11/2026). The agent then moved a monitor at 100 % to 5 % (BL-003). Patched, the same 200 reads: none wrong, none
failed; about 180 ms a read instead of 110. Upstream 1.3.2 (18/11/2026) reads the same way; its maintainer notes the
missing reply validation in waydabber/m1ddc#37.

Side effect: `get input-alt` (LG's alternate address) never got a real reply on that LG either; upstream prints `0`,
the patched build says there's no valid reply.

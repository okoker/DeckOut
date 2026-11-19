# Known Issues

Edge cases, uncertain solutions, and accepted limitations we're aware of but not ready to act on.

- **Know what to do, just not now?** → `BACKLOG.md`
- **Don't know the fix / need more info / accepting for now?** → here.

When ready to address: move to `BACKLOG.md` or `TODO.md`, delete from here.

Next free ID: KI-010

---

| ID | Date | Description |
|----|------|-------------|
| KI-001 | 27/03/2026 | macOS IOKit HID requires CFRunLoop running for input report delivery — Swift uses CFRunLoopRun() on main thread |
| ~~KI-002~~ | 27/03/2026 | ~~ZR7Player volume IPC~~ — Resolved: DistributedNotifications (com.zr7.volumeUp/Down/muteToggle) |
| ~~KI-003~~ | 27/03/2026 | ~~configKey mismatch~~ — Resolved: configKey property wired into dispatcher |
| ~~KI-004~~ | 27/03/2026 | ~~BAT image protocol~~ — Resolved: working, previous corruption was sendPacket report-ID bug |
| KI-005 | 27/03/2026 | IOHIDDeviceSetReport requires data WITHOUT report ID prefix byte — unlike hidapi which includes it. Fixed in sendPacket but be aware when adding new packet types |
| KI-008 | 02/11/2026 | The first launch of a newly written ad hoc agent binary is sometimes killed by macOS (`SIGKILL (Code Signature Invalid)`, `Launch Constraint Violation (Constraint not matched)`). Hand install: launchd relaunches ~10 s later and it runs (seen on both installs on 02/11/2026, not on 19/11/2026's). DeckOut's agent (registered with `SMAppService`, 19/11/2026): seen when the bundle was replaced while the agent was unregistered and then registered again; launchd dropped the job, Background Task Management invalidated it, and launchd then couldn't find the program (`No such process: Contents/MacOS/DeckOutAgent`) until unregister + register, which the app now does when its agent doesn't answer. Not seen when the bundle was replaced while the agent stayed registered (the update path). Cause unknown; whether a Developer ID signature avoids it is untested. |
| KI-009 | 19/11/2026 | The N4 gets no power from the dock's USB-C port (the only USB-C port tried) after being unplugged for more than a few seconds: dark, absent from the USB tree. It powers up only if the port is already live (e.g. a phone plugged in first, then the cable swapped). On USB-A (A-to-C cable) it works every time. Most likely the N4's USB-C socket lacks the resistors that tell a USB-C port to switch power on; not confirmed with a meter. Workaround: connect the N4 to USB-A. |

## Accepted Risks

| ID | Date | Description |
|----|------|-------------|
| KI-006 | 01/04/2026 | USB device spoofing: device matching trusts VID/PID only. A spoofed USB device with matching IDs could drive configured actions. Accepted: requires physical access to plug in a malicious device, and actions are limited to user-level privileges. No device-specific handshake available in hardware. |
| KI-007 | 01/04/2026 | Optimistic brightness cache: HUD shows brightness value before async m1ddc write confirms success. If m1ddc fails silently, displayed value may not match hardware. Accepted: m1ddc failures are rare in practice and cache re-syncs on next idle→active transition. |

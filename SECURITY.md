# Security Policy

## Reporting a Vulnerability

Please **do not** report security issues via public GitHub issues, pull requests, or discussions.

Instead, use GitHub's private vulnerability reporting:

1. Go to the **Security** tab of this repository
2. Click **Report a vulnerability**
3. Fill in the private advisory form

Your report will be visible only to the maintainers. You can include reproduction steps, proof-of-concept code, affected versions, and any other detail needed — the form supports markdown and attachments.

## What to expect

- Acknowledgement of your report within a reasonable time
- A private thread to discuss the issue and coordinate a fix
- Credit in the published advisory once a fix ships (unless you ask to remain anonymous)

## Scope

Reports about DeckOut are in scope: the app, its background daemon and the connection between them (USB HID handling, config parsing, action dispatch, the code-signature checks on that connection, privilege boundaries, etc.). Issues in the bundled third-party code (m1ddc, Phosphor Icons) should be reported upstream.

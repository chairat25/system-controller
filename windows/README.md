# System Controller for Windows

A small companion that pairs a Windows PC with the System Controller Mac app (1.7 or later), so the desktop
mascots walk between the Mac and the PC. Each computer keeps its own animal, colour and size; a visitor looks the
way its home computer set it up.

## Run

1. Install Python 3.13 or newer from python.org (keep "tcl/tk" ticked).
2. Double-click `run.bat`. The first run installs `zeroconf`, `cryptography` and `pillow` into `.venv`.
3. When Windows Firewall asks, allow **Private networks**.

Or build one `.exe`: run `build-exe.bat`, then use `dist\SystemController.exe`.

## Pair with a Mac

1. On the Mac: menu bar icon → gear → Sync → turn on **Mascot roams between Macs** → **Pair…**.
2. On the PC: **Pair with a Mac…**, then **Pair** next to the Mac (or pick the PC on the Mac).
3. Both screens show the same six digits: click **Confirm** on both.
4. Set **Side** on both: on the PC, the edge the Mac is beyond; on the Mac, the edge the PC is beyond.

## What works

- Pairing (same six-digit check and keys as Mac to Mac), TLS 1.2 PSK connection, several paired computers.
- Mascots walk or are thrown across the edge in both directions, keep their look, colour and size, and are sent
  back instead of vanishing when the other side cannot take them.
- Click a mascot to make it hop; drag and let go to throw it.
- Not yet: wallpaper sync, window climbing on Windows.

Settings and pairing keys live in `%APPDATA%\SystemController`. The protocol is in `../docs/LAN-PROTOCOL.md`.

## Develop

    python -m venv .venv && .venv/bin/pip install -r requirements.txt pytest
    .venv/bin/python -m pytest tests
    .venv/bin/python -m syscontrol --headless --data /tmp/pc --pair --send right   # scripted test companion

Testing against the Mac app on the same Mac needs `SYSCONTROL_LOOPBACK=1`, and even then macOS cannot dial a
companion on the same machine (its mDNS lookups for the companion's host name go to the loopback interface), so
only the companion-dials-Mac direction works there. Between two real computers both directions work.

# Portside

A native macOS menu bar app that shows what's listening on **localhost** and lets you act on it. Nothing else — it is not a general network tool.

Each row is something you can open at `http://localhost:PORT`. Click to open it in your browser, ⌘-click to copy the URL, right-click for more (open cwd in Terminal, reveal in Finder, kill). Dev servers are tagged (Vite, Next, Postgres, …), pinned ports stay at the top even when they're down, and you can rename a port to something memorable.

## Localhost only — by design

The list only contains ports reachable via loopback:

- **Included:** binds to `127.0.0.0/8`, `::1`, and wildcards (`*` / `0.0.0.0` / `::`) — wildcard binds are reachable through loopback.
- **Excluded:** binds to a specific LAN/external interface (`192.168.1.20:5000`, `10.0.0.4:8080`), link-local (`fe80::…`), and **all UDP**. TCP listeners only.
- A port bound on both IPv4 and IPv6 loopback shows once.

There is deliberately no "show all ports" toggle, interface picker, or remote host support.

System daemons (root-owned under `/usr/libexec`, `/usr/sbin`, `/System`, plus `rapportd`, `sharingd`, `ControlCenter`, AirPlay) are hidden by default — one checkbox in Settings shows them. Processes you started are never hidden.

## Build

Requires macOS 14+ and the Swift toolchain.

```sh
./build.sh            # runs tests, builds release, assembles dist/Portside.app
./build.sh --install  # also copies it to /Applications
```

`build.sh` needs full **Xcode** to run the unit tests (`swift test` uses the XCTest/Testing runner that Command Line Tools alone don't ship). Without Xcode it prints a warning and still builds the app; install Xcode and run `swift test` to execute the tests.

If `assets/AppIcon.png` exists, the build generates `AppIcon.icns` and wires it into the bundle. Otherwise the app uses the default icon.

## Install

`./build.sh --install` puts `Portside.app` in `/Applications`. Launch it and a network icon with a listener count appears in your menu bar. Enable **Launch at login** in Settings (uses `SMAppService`).

## Privacy

Everything is local. Portside runs `lsof` and `ps` on your machine to read listeners and enrich them, and does nothing else — no sandbox exception is needed because it makes **no network calls of any kind** and sends nothing anywhere.

## Layout

- `Sources/PortsideCore` — pure, unit-tested logic: the `lsof` parser, localhost filter, runtime/label detection, daemon filter, kill logic.
- `Sources/Portside` — the SwiftUI `MenuBarExtra` app.
- `Tests/PortsideCoreTests` — parser, filter, enrichment, and uptime tests.

# Portside

A native macOS menu bar app that shows what's listening on **localhost** and lets you act on it. Nothing else — it is not a general network tool.

Each row is something you can open at `http://localhost:PORT`. Click to open it in your browser, ⌘-click to copy the URL, right-click for more (open cwd in Terminal, reveal in Finder, kill). Dev servers are tagged (Vite, Next, Postgres, …), pinned ports stay at the top even when they're down, and you can rename a port to something memorable.

Docker-published ports are named by their container. Docker Desktop serves every published port from one host process, so `lsof` and `ps` see ten identical rows; Portside asks Docker's local socket which container is behind each port and shows that instead, with the image on the second line.

## What a row tells you

**The name** is the first thing that actually identifies the process:

1. a label you set yourself,
2. the container name, for a Docker-published port,
3. the `name` from the `package.json` in the process's working directory,
4. the process name.

A directory only names a row when something confirms the process belongs to it — that `package.json`, or a recognised runtime. Otherwise a tool that merely started in a checkout would take the project's name: `adb`, auto-started by an Android command inside `~/work/san-diego`, reads as `adb`, not as `san-diego`.

**The second line** is the container image, the working directory, or the process name when nothing else has identified the row. It doesn't repeat what the first line already says; a row with no directory shows `pid 913` instead.

**The tags** are the runtime (Vite, Next, Django, Postgres, Docker, …) when one is recognised, and `LAN` when the port is bound to every interface (`*` / `0.0.0.0` / `::`) rather than to loopback.

A `LAN` port answers on this Mac's network address, so other machines on the network can reach it — Docker publishes to `0.0.0.0` by default, so container ports normally carry the tag. Publish as `127.0.0.1:5433:5432` to keep one private. Portside only reports what `lsof` already knows; it never probes anything.

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

Everything is local. Portside runs `lsof` and `ps` on your machine to read listeners and enrich them, and — when a Docker-published port is listening — reads the container list from Docker's unix socket at `~/.docker/run/docker.sock` (or `/var/run/docker.sock`). It does nothing else: no sandbox exception is needed because it makes **no network calls of any kind** and sends nothing anywhere. The Docker read is a local socket, never the network, and is skipped entirely when no Docker-owned port is listening.

## Layout

- `Sources/PortsideCore` — pure, unit-tested logic: the `lsof` parser, localhost filter, runtime/label detection, daemon filter, Docker port mapping, kill logic.
- `Sources/Portside` — the SwiftUI `MenuBarExtra` app.
- `Tests/PortsideCoreTests` — parser, filter, enrichment, Docker mapping, and uptime tests.

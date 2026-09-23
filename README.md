# Portside

A native macOS menu bar app that shows what's listening on **localhost** and lets you act on it. Nothing else — it is not a general network tool.

Each row is something you can open at `http://localhost:PORT`. Click to open it in your browser, ⌘-click to copy the URL, right-click for more (open the working directory in Terminal, Finder, or any installed editor — VS Code, Cursor, Zed, Windsurf, Sublime, a JetBrains IDE — plus pin, rename and kill). For a container that directory is the compose stack it belongs to, not Docker's internal storage. Dev servers are tagged (Vite, Next, Postgres, …), pinned ports stay at the top even when they're down, and you can rename a port to something memorable.

Docker-published ports are named by their container. Docker Desktop serves every published port from one host process, so `lsof` and `ps` see ten identical rows; Portside asks Docker's local socket which container is behind each port and shows that instead, with the image on the second line.

## What a row tells you

**The name** is the first thing that actually identifies the process:

1. a label you set yourself,
2. the container name, for a Docker-published port,
3. the checkout it runs from,
4. the process name.

The checkout beats the `package.json` name on purpose. Thirty parallel worktrees of one repo all call themselves the same thing in `package.json`, so that name is the one field that *cannot* tell them apart — `san-diego` can. Inside a monorepo the enclosing checkout comes too, since `apps/storefront` is called `storefront` in every copy: `san-diego/storefront`.

If you use [Conductor](https://conductor.build), a renamed workspace shows the name you gave it. Conductor keeps that name in its own database and never renames the directory, so the folder stays `warsaw` for a workspace you call Marketing. Portside reads the mapping read-only and falls back to the directory name when Conductor isn't installed. Because a rename touches nothing on disk, the name is recomputed on every scan rather than cached — rename a workspace and the row follows on the next refresh.

Container rows are named the same way. `chennai-postgres-1` is compose's own construction — stack directory, service, replica index — so Portside reads the compose labels instead and shows `GMaps link/postgres`: the workspace the stack lives in, and the service within it. Containers started outside compose keep their own name.

A directory only names a row when something confirms the process belongs to it — a `package.json`, or a recognised runtime. Otherwise a tool that merely started in a checkout would take its name: `adb`, auto-started by an Android command inside `~/work/san-diego`, reads as `adb`, not as `san-diego`.

**The second line** is the container image, the `package.json` name, the working directory, or the process name — whichever is the first thing the title didn't already say. A row with nothing left to add shows `pid 913`.

**The tags** are the runtime (Vite, Next, Django, Postgres, Docker, …) when one is recognised, tinted with that project's brand colour, and `LAN` when the port is bound to every interface (`*` / `0.0.0.0` / `::`) rather than to loopback. Colour is a wash behind the label rather than the text itself, so the tag stays readable in both light and dark; the word always carries the meaning.

A `LAN` port answers on this Mac's network address, so other machines on the network can reach it — Docker publishes to `0.0.0.0` by default, so container ports normally carry the tag. Publish as `127.0.0.1:5433:5432` to keep one private. Portside only reports what `lsof` already knows; it never probes anything.

## Your ports, then everything else

Ports you're working on sort first. Spotify, a helper daemon and an updater sort below a **Background apps** heading, and **Show background apps** in Settings hides them entirely.

The split needs no list of app names: a GUI app is launched by Finder or launchd and inherits `/` as its working directory, while a dev server is started from a checkout and inherits that. So a row is yours when it runs from a real directory, or when a container stands behind it. Whatever you install next month is classified correctly without Portside knowing it exists.

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
./build.sh --install  # also copies it to /Applications, restarting it if it was running
```

To update an existing install:

```sh
git pull && ./build.sh --install
```

The restart matters: a running app keeps executing from its old bundle even after that bundle is replaced, so without it you'd stay on the previous build with no sign anything had changed.

The build is stamped with `git describe`, and Settings shows it — a tagged commit reads `1.2.0`, anything after one reads `1.2.0-4-gabc1234`, and uncommitted changes add `-dirty`. That's how you tell which build you're running.

`build.sh` needs full **Xcode** to run the unit tests (`swift test` uses the XCTest/Testing runner that Command Line Tools alone don't ship). Without Xcode it prints a warning and still builds the app; install Xcode and run `swift test` to execute the tests.

If `assets/AppIcon.png` exists, the build generates `AppIcon.icns` and wires it into the bundle. Otherwise the app uses the default icon.

## Install

`./build.sh --install` puts `Portside.app` in `/Applications`. Launch it and a network icon with a listener count appears in your menu bar. Enable **Launch at login** in Settings (uses `SMAppService`).

## Privacy

Everything is local. Portside runs `lsof` and `ps` on your machine to read listeners and enrich them; when a Docker-published port is listening it reads the container list from Docker's unix socket at `~/.docker/run/docker.sock` (or `/var/run/docker.sock`); and when something is running from a Conductor workspace it reads workspace names from Conductor's own SQLite file, opened read-only. It does nothing else: no sandbox exception is needed because it makes **no network calls of any kind** and sends nothing anywhere. The Docker read is a local socket, never the network, and is skipped entirely when no Docker-owned port is listening.

## Layout

- `Sources/PortsideCore` — pure, unit-tested logic: the `lsof` parser, localhost filter, runtime/label detection, row naming, daemon filter, Docker port mapping, Conductor workspace names, kill logic.
- `Sources/Portside` — the SwiftUI `MenuBarExtra` app.
- `Tests/PortsideCoreTests` — parser, filter, enrichment, Docker mapping, and uptime tests.

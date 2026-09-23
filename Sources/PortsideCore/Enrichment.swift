import Foundation

// Pure, unit-testable enrichment logic. No I/O here — callers pass in the
// strings they read from `ps` / `lsof` / `package.json`.

/// Best-effort dev-server label from a process's full command line.
/// Framework runners (Vite, Next…) are checked before the interpreter they run
/// on (node, python) since e.g. Vite *is* a node process. Returns nil when
/// nothing matches — caller falls back to the process name.
public func runtimeLabel(command: String, processName: String) -> String? {
    let c = command.lowercased()

    // ordered: most specific first
    let rules: [(needles: [String], label: String)] = [
        (["vite"], "Vite"),
        (["next dev", "next-server", "next start", "/next/", "\\next\\"], "Next"),
        (["nuxt"], "Nuxt"),
        (["remix"], "Remix"),
        (["astro"], "Astro"),
        (["webpack"], "Webpack"),
        (["uvicorn"], "uvicorn"),
        (["gunicorn"], "gunicorn"),
        (["manage.py runserver", "django"], "Django"),
        (["flask"], "Flask"),
        (["rails", "puma"], "Rails"),
        (["deno"], "Deno"),
        (["bun "], "Bun"),
        (["postgres"], "Postgres"),
        (["redis-server", "redis-serv"], "Redis"),
        (["mysqld", "mariadb"], "MySQL"),
        (["mongod"], "Mongo"),
        (["elasticsearch", "org.elasticsearch"], "Elasticsearch"),
        (["com.docker", "docker-proxy", "vpnkit", "orbstack", "orb "], "Docker"),
        (["go run", "__debug_bin"], "Go"),
        (["node"], "Node"),
        (["python"], "Python"),
    ]

    for rule in rules where rule.needles.contains(where: { c.contains($0) }) {
        return rule.label
    }
    return nil
}

/// System daemons hidden by default. Match by known name or by root-owned
/// executables under system paths. User-owned, non-daemon processes are never
/// hidden — if the user started it, they see it.
public func isSystemDaemon(user: String, execPath: String, processName: String) -> Bool {
    let name = processName.lowercased()
    // lsof truncates to ~9 chars, so match on prefixes
    let daemonPrefixes = ["rapportd", "sharingd", "controlce", "airplay"]
    if daemonPrefixes.contains(where: { name.hasPrefix($0) }) { return true }

    if user == "root" {
        let systemDirs = ["/usr/libexec", "/usr/sbin", "/System"]
        if systemDirs.contains(where: { execPath.hasPrefix($0) }) { return true }
    }
    return false
}

/// `name` field from a package.json blob, or nil if absent/unparseable.
public func parsePackageName(fromJSON json: String) -> String? {
    guard let data = json.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let name = obj["name"] as? String,
          !name.isEmpty
    else { return nil }
    return name
}

/// Short workspace label from a cwd: the last 2 *meaningful* path components,
/// prefixed with `…/` when truncated. Structural monorepo/worktree dirs
/// (`workspaces`, `apps`, `packages`, `src`) are dropped first so the segment
/// that actually identifies the checkout survives — e.g.
/// `…/workspaces/core/shanghai/apps/storefront` → `…/shanghai/storefront`,
/// distinguishing it from the same app in another workspace.
public func workspaceLabel(cwd: String, maxComponents: Int = 2) -> String? {
    let noise: Set<String> = ["workspaces", "apps", "packages", "src"]
    let all = cwd.split(separator: "/").map(String.init)
    guard !all.isEmpty else { return nil }
    // keep the leaf even if it's a noise word; strip noise only from the middle
    let leaf = all[all.count - 1]
    let meaningful = all.dropLast().filter { !noise.contains($0) } + [leaf]

    let tail = meaningful.suffix(maxComponents)
    let prefix = meaningful.count > maxComponents ? "…/" : "/"
    return prefix + tail.joined(separator: "/")
}

/// Directories that never name a row: root, home, temp, and app-support
/// storage — `~/Library/Containers/com.docker.docker/Data` is nine
/// Docker-mapped ports all calling themselves "Data".
private func isThrowawayDir(_ cwd: String, homeDir: String) -> Bool {
    if cwd.isEmpty || cwd == "/" || cwd == homeDir { return true }
    let skipDirs = [
        "/tmp", "/private/tmp", "/var/folders", "/private/var/folders",
        homeDir + "/Library", "/Library",
    ]
    // match whole path components, so `~/Library-notes` isn't taken for `~/Library`
    return skipDirs.contains { cwd == $0 || cwd.hasPrefix($0 + "/") }
}

/// Project name: package.json `name` > cwd basename > nil.
public func projectName(cwd: String?, packageName: String?, homeDir: String) -> String? {
    if let packageName, !packageName.isEmpty { return packageName }
    guard let cwd, !isThrowawayDir(cwd, homeDir: homeDir) else { return nil }

    let base = (cwd as NSString).lastPathComponent
    return base.isEmpty ? nil : base
}

/// The checkout a process runs from: the directory name, and the enclosing
/// checkout too when that name sits inside a monorepo subdir — `apps/storefront`
/// is called `storefront` in every copy of the repo, `san-diego/storefront`
/// says which copy.
public func checkoutName(cwd: String, workspaceNames: [String: String] = [:]) -> String? {
    let noise: Set<String> = ["workspaces", "apps", "packages", "src"]

    // a renamed Conductor workspace: the folder is `warsaw`, the user calls it
    // "Marketing", and only Conductor's database knows that
    if let workspace = conductorWorkspace(for: cwd, names: workspaceNames) {
        guard let leaf = workspace.rest.last, !noise.contains(leaf) else { return workspace.name }
        return "\(workspace.name)/\(leaf)"
    }

    let all = cwd.split(separator: "/").map(String.init)
    guard let leaf = all.last else { return nil }

    let parents = all.dropLast()
    guard let parent = parents.last else { return leaf }
    if !noise.contains(parent) && !noise.contains(leaf) { return leaf }

    guard let enclosing = parents.last(where: { !noise.contains($0) }) else { return leaf }
    return noise.contains(leaf) ? enclosing : "\(enclosing)/\(leaf)"
}

/// The name a row leads with.
///
/// A directory only gets to name the row when something confirms the process
/// belongs to it — its own `package.json`, or a recognised runtime. Otherwise a
/// tool that merely happened to start in that directory (adb, cloudflared)
/// takes the project's name and says nothing about itself; the caller falls
/// back to the process name instead.
///
/// Given that evidence, the checkout wins over the `package.json` name: thirty
/// parallel worktrees of one repo share a package name, so it is the one thing
/// that cannot tell them apart. The package name moves to the second line.
public func rowName(cwd: String?, packageName: String?, runtime: String?, homeDir: String,
                    workspaceNames: [String: String] = [:]) -> String? {
    guard packageName != nil || runtime != nil else { return nil }
    if let cwd, !isThrowawayDir(cwd, homeDir: homeDir),
       let checkout = checkoutName(cwd: cwd, workspaceNames: workspaceNames) {
        return checkout
    }
    return packageName
}

/// A row is the user's own work when it runs from a real directory, or when a
/// container stands behind it. Background apps — Spotify, a helper daemon, an
/// updater — are launched by Finder or launchd and inherit `/`, so they have no
/// working directory to show.
public func isBackgroundApp(cwd: String?, hasContainer: Bool, homeDir: String) -> Bool {
    if hasContainer { return false }
    guard let cwd, !isThrowawayDir(cwd, homeDir: homeDir) else { return true }
    return false
}

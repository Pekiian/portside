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

/// Project name: package.json `name` > cwd basename > nil.
/// The basename is dropped when cwd is a throwaway location (root, home, temp).
public func projectName(cwd: String?, packageName: String?, homeDir: String) -> String? {
    if let packageName, !packageName.isEmpty { return packageName }
    guard let cwd, !cwd.isEmpty else { return nil }

    let uninteresting = ["/", homeDir]
    if uninteresting.contains(cwd) { return nil }

    let tempPrefixes = ["/tmp", "/private/tmp", "/var/folders", "/private/var/folders"]
    if tempPrefixes.contains(where: { cwd.hasPrefix($0) }) { return nil }

    let base = (cwd as NSString).lastPathComponent
    return base.isEmpty ? nil : base
}

import Foundation

// Conductor keeps a workspace's display name in its own database and never
// renames the directory, so the folder `core/warsaw` belongs to a workspace its
// owner calls "Marketing". Reading the directory name shows a word they don't
// recognise — the rename only ever existed in Conductor's UI.

/// Workspace directory → the name Conductor shows for it. Empty when Conductor
/// isn't installed, the schema moved, or nothing has been renamed.
func conductorWorkspaceNames() async -> [String: String] {
    let db = NSHomeDirectory() + "/Library/Application Support/com.conductor.app/conductor.db"
    guard FileManager.default.fileExists(atPath: db) else { return [:] }

    // read-only URI so a running Conductor is never blocked or modified
    let out = await Shell.run("/usr/bin/sqlite3", [
        "-readonly", "-separator", "\t", "file:\(db)?mode=ro",
        "SELECT workspace_path, workspace_name FROM workspaces "
            + "WHERE workspace_name IS NOT NULL AND workspace_name != '';",
    ])
    return parseConductorWorkspaces(out)
}

/// Parse the tab-separated `path<TAB>name` rows. Paths contain spaces
/// ("Black Pearl Ventures"), names can too, so only the first tab splits.
public func parseConductorWorkspaces(_ out: String) -> [String: String] {
    var names: [String: String] = [:]
    for line in out.split(whereSeparator: \.isNewline) {
        guard let tab = line.firstIndex(of: "\t") else { continue }
        let path = String(line[..<tab])
        let name = String(line[line.index(after: tab)...])
        guard !path.isEmpty, !name.isEmpty else { continue }
        names[path] = name
    }
    return names
}

/// The workspace a path sits in, and how far below it the path goes.
/// Longest match wins, so a workspace nested inside another still resolves.
public func conductorWorkspace(for cwd: String, names: [String: String]) -> (name: String, rest: [String])? {
    var best: (path: String, name: String)?
    for (path, name) in names where cwd == path || cwd.hasPrefix(path + "/") {
        if best == nil || path.count > best!.path.count { best = (path, name) }
    }
    guard let match = best else { return nil }
    let rest = cwd.dropFirst(match.path.count).split(separator: "/").map(String.init)
    return (match.name, rest)
}

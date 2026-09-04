import Foundation
import Darwin

/// Per-PID enrichment that doesn't change over a process's lifetime, cached so
/// we don't re-shell on every 2s refresh.
private struct ProcessInfo_ {
    var cwd: String?
    var command: String?
    var execPath: String
    var displayName: String
    var runtime: String?
    var projectName: String?
    var startedAt: Date?
    /// Kernel start time, used only to tell a recycled pid from the original.
    /// nil for pids libproc won't answer for (root-owned) — those just keep
    /// their cache entry, which is what the old code did for every pid.
    var procStart: Date?
}

/// Runs `lsof`, parses, enriches, and applies the system-daemon filter.
/// An actor so the per-PID cache is touched from one place; all shelling is
/// async and off the main thread.
public actor PortScanner {
    private var cache: [Int: ProcessInfo_] = [:]
    private let homeDir = NSHomeDirectory()

    public init() {}

    /// Full scan. `showSystem` keeps daemons in the result when true.
    public func scan(showSystem: Bool) async -> [Listener] {
        let lsofOut = await Shell.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN"])
        var listeners = parseListeners(from: lsofOut)
        guard !listeners.isEmpty else { evictStalePIDs(alive: []); return [] }

        let pids = Array(Set(listeners.map(\.pid)))
        evictStalePIDs(alive: Set(pids))
        await ensureCached(pids: pids)

        for i in listeners.indices {
            guard let info = cache[listeners[i].pid] else { continue }
            listeners[i].cwd = info.cwd
            listeners[i].command = info.command
            listeners[i].runtime = info.runtime
            listeners[i].projectName = info.projectName
            listeners[i].startedAt = info.startedAt
            if !info.displayName.isEmpty { listeners[i].processName = info.displayName }
        }

        // one socket read resolves every Docker-published port at once
        if listeners.contains(where: { $0.runtime == "Docker" }) {
            let containers = await dockerContainers()
            for i in listeners.indices where listeners[i].runtime == "Docker" {
                guard let container = containers[listeners[i].port] else { continue }
                listeners[i].projectName = container.name
                listeners[i].detail = container.image
            }
        }

        if !showSystem {
            listeners = listeners.filter { l in
                guard let info = cache[l.pid] else { return true }
                return !isSystemDaemon(user: l.user, execPath: info.execPath, processName: l.processName)
            }
        }
        return listeners
    }

    private func evictStalePIDs(alive: Set<Int>) {
        for pid in cache.keys where !alive.contains(pid) { cache[pid] = nil }
    }

    private func ensureCached(pids: [Int]) async {
        // a recycled pid gets a fresh start time — drop the previous tenant's info
        for pid in pids where cache[pid] != nil && cache[pid]?.procStart != processStartTime(pid) {
            cache[pid] = nil
        }
        let missing = pids.filter { cache[$0] == nil }
        guard !missing.isEmpty else { return }

        let pidList = missing.map(String.init).joined(separator: ",")
        // one ps call for command + start time; comm= gives the full exec path
        async let psOut = Shell.run("/bin/ps", ["-o", "pid=,lstart=,comm=", "-p", pidList])
        async let cwdOut = Shell.run("/usr/sbin/lsof", ["-a", "-p", pidList, "-d", "cwd", "-Fpn"])
        // one ps for the full argv (command=) keyed per pid
        async let argvOut = Shell.run("/bin/ps", ["-o", "pid=,command=", "-p", pidList])

        let psInfo = parsePS(await psOut)
        let cwds = parseCWD(await cwdOut)
        let argv = parseArgv(await argvOut)

        for pid in missing {
            let execPath = psInfo[pid]?.execPath ?? ""
            let command = argv[pid] ?? execPath
            let displayName = (execPath as NSString).lastPathComponent
            let cwd = cwds[pid]
            let pkgName = cwd.flatMap { readPackageName(cwd: $0) }
            let runtime = runtimeLabel(command: command, processName: displayName)
            cache[pid] = ProcessInfo_(
                cwd: cwd,
                command: command,
                execPath: execPath,
                displayName: displayName,
                runtime: runtime,
                projectName: rowName(cwd: cwd, packageName: pkgName, runtime: runtime, homeDir: homeDir),
                startedAt: psInfo[pid]?.startedAt,
                procStart: processStartTime(pid)
            )
        }
    }

    private func readPackageName(cwd: String) -> String? {
        let path = (cwd as NSString).appendingPathComponent("package.json")
        guard let json = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return parsePackageName(fromJSON: json)
    }
}

// MARK: - ps / lsof field parsing

/// Kernel start time for a pid — no shellout, so it's cheap enough to check
/// every scan. Returns nil when libproc denies the pid (root-owned processes),
/// which is why uptime still comes from `ps lstart` instead of this.
func processStartTime(_ pid: Int) -> Date? {
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    guard proc_pidinfo(Int32(pid), PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
    return Date(timeIntervalSince1970: Double(info.pbi_start_tvsec))
}

private func parsePS(_ out: String) -> [Int: (execPath: String, startedAt: Date?)] {
    var result: [Int: (String, Date?)] = [:]
    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "en_US_POSIX")
    fmt.dateFormat = "EEE MMM d HH:mm:ss yyyy"

    for line in out.split(whereSeparator: \.isNewline) {
        // "PID Www Mmm DD HH:MM:SS YYYY /path/to/exec"
        let tokens = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard tokens.count >= 7, let pid = Int(tokens[0]) else { continue }
        let lstart = tokens[1...5].joined(separator: " ")
        let execPath = tokens[6...].joined(separator: " ")
        result[pid] = (execPath, fmt.date(from: lstart))
    }
    return result
}

private func parseArgv(_ out: String) -> [Int: String] {
    var result: [Int: String] = [:]
    for line in out.split(whereSeparator: \.isNewline) {
        let trimmed = line.drop(while: { $0 == " " })
        guard let space = trimmed.firstIndex(of: " "),
              let pid = Int(trimmed[..<space]) else { continue }
        result[pid] = String(trimmed[trimmed.index(after: space)...])
    }
    return result
}

/// Parse `lsof -Fpn` field output: lines start with `p<pid>` then `n<path>`.
private func parseCWD(_ out: String) -> [Int: String] {
    var result: [Int: String] = [:]
    var currentPID: Int?
    for line in out.split(whereSeparator: \.isNewline) {
        guard let tag = line.first else { continue }
        let value = String(line.dropFirst())
        switch tag {
        case "p": currentPID = Int(value)
        case "n": if let pid = currentPID { result[pid] = value }
        default: break
        }
    }
    return result
}

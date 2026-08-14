import Foundation

/// A parsed TCP loopback address (host + port + family).
public struct BindAddress: Equatable, Hashable {
    public enum Family: String, Equatable, Hashable { case ipv4, ipv6 }

    public let host: String
    public let port: Int
    public let family: Family

    /// Parse an lsof NAME field like `127.0.0.1:3000`, `[::1]:3000`, `*:5432`,
    /// `[fe80::1%en0]:5000`. `typeToken` is lsof's TYPE column (IPv4/IPv6).
    public init?(raw: String, typeToken: String) {
        let family: Family = typeToken.contains("6") ? .ipv6 : .ipv4
        let host: String
        let portStr: String

        if raw.hasPrefix("[") {
            // bracketed IPv6: [host]:port  or  [host%zone]:port
            guard let close = raw.firstIndex(of: "]") else { return nil }
            host = String(raw[raw.index(after: raw.startIndex)..<close])
            let rest = raw[raw.index(after: close)...]
            guard rest.hasPrefix(":") else { return nil }
            portStr = String(rest.dropFirst())
        } else {
            // host:port — split on the LAST colon (host has no colons here)
            guard let colon = raw.lastIndex(of: ":") else { return nil }
            host = String(raw[..<colon])
            portStr = String(raw[raw.index(after: colon)...])
        }

        guard let port = Int(portStr), port > 0 else { return nil }
        self.host = host
        self.port = port
        self.family = family
    }

    /// True when reachable via `http://localhost:PORT`: loopback or a wildcard
    /// bind. LAN/external interface binds return false.
    public var isLocalhostReachable: Bool {
        // strip IPv6 zone id, e.g. fe80::1%en0
        let h = host.split(separator: "%").first.map(String.init) ?? host
        if h == "*" || h == "0.0.0.0" || h == "::" { return true }
        if h == "::1" { return true }
        // ponytail: whole 127.0.0.0/8 is loopback, not only 127.0.0.1
        if h.hasPrefix("127.") { return true }
        return false
    }
}

/// One localhost TCP listener. Parser fills the base fields; enrichment
/// (cwd/project/runtime/uptime) and user prefs (label/pin) are layered on later.
public struct Listener: Identifiable, Equatable {
    // from lsof
    public var port: Int
    public var pid: Int
    public var processName: String
    public var user: String
    public var bind: BindAddress

    // enrichment (filled after parsing)
    public var cwd: String?
    public var projectName: String?
    public var runtime: String?
    public var command: String?
    public var startedAt: Date?

    // user prefs
    public var customLabel: String?
    public var pinned: Bool

    public var id: Int { port }

    public init(
        port: Int,
        pid: Int,
        processName: String,
        user: String,
        bind: BindAddress,
        cwd: String? = nil,
        projectName: String? = nil,
        runtime: String? = nil,
        command: String? = nil,
        startedAt: Date? = nil,
        customLabel: String? = nil,
        pinned: Bool = false
    ) {
        self.port = port
        self.pid = pid
        self.processName = processName
        self.user = user
        self.bind = bind
        self.cwd = cwd
        self.projectName = projectName
        self.runtime = runtime
        self.command = command
        self.startedAt = startedAt
        self.customLabel = customLabel
        self.pinned = pinned
    }

    /// What the row shows as its primary name: custom label > project > process.
    public var displayName: String {
        customLabel ?? projectName ?? processName
    }
}

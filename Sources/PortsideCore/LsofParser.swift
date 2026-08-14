import Foundation

/// Parse the output of `lsof -nP -iTCP -sTCP:LISTEN` into localhost listeners.
///
/// Column layout (whitespace-separated), NAME may be padded:
///   COMMAND  PID  USER  FD  TYPE  DEVICE  SIZE/OFF  NODE  NAME  (LISTEN)
///
/// COMMAND can contain spaces, so we anchor on the seven fixed trailing columns
/// and treat everything before them as `COMMAND... PID USER`.
public func parseListeners(from lsofOutput: String) -> [Listener] {
    var byPort: [Int: Listener] = [:]

    for rawLine in lsofOutput.split(whereSeparator: \.isNewline) {
        guard let listener = parseLine(String(rawLine)) else { continue }
        guard listener.bind.isLocalhostReachable else { continue }
        // dedupe by port: same port on v4 + v6 loopback shows once (keep first)
        if byPort[listener.port] == nil {
            byPort[listener.port] = listener
        }
    }

    return byPort.values.sorted { $0.port < $1.port }
}

/// Parse a single lsof line. Returns nil for headers, non-TCP, or malformed rows.
func parseLine(_ line: String) -> Listener? {
    let tokens = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    // need at least COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME (LISTEN)
    guard tokens.count >= 10 else { return nil }
    guard tokens.last == "(LISTEN)" else { return nil }

    let n = tokens.count
    // trailing columns, from the right:
    //   n-1 (LISTEN) | n-2 NAME | n-3 NODE | n-4 SIZE/OFF | n-5 DEVICE | n-6 TYPE | n-7 FD
    let addr = tokens[n - 2]
    let node = tokens[n - 3]
    let typeToken = tokens[n - 6]
    guard node == "TCP" else { return nil }

    // everything before FD is: COMMAND... PID USER
    let head = tokens[0 ..< (n - 7)]
    guard head.count >= 3 else { return nil }
    let user = head[head.count - 1]
    guard let pid = Int(head[head.count - 2]) else { return nil }
    let processName = head[0 ..< (head.count - 2)].joined(separator: " ")

    guard let bind = BindAddress(raw: addr, typeToken: typeToken) else { return nil }

    return Listener(
        port: bind.port,
        pid: pid,
        processName: processName,
        user: user,
        bind: bind
    )
}

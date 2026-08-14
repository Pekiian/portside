import Testing
@testable import PortsideCore

// Realistic `lsof -nP -iTCP -sTCP:LISTEN` header. Parser must skip it.
private let header = "COMMAND     PID   USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME"

private func out(_ lines: String...) -> String {
    ([header] + lines).joined(separator: "\n")
}

@Test func ipv4Loopback() {
    let l = parseListeners(from: out(
        "node      41231  pedro   23u  IPv4 0x1a2b3c4d5e6f7a8b      0t0  TCP 127.0.0.1:3000 (LISTEN)"
    ))
    #expect(l.count == 1)
    #expect(l[0].port == 3000)
    #expect(l[0].pid == 41231)
    #expect(l[0].processName == "node")
    #expect(l[0].user == "pedro")
    #expect(l[0].bind.family == .ipv4)
}

@Test func ipv6Loopback() {
    let l = parseListeners(from: out(
        "node      41231  pedro   24u  IPv6 0x00aa11bb22cc33dd      0t0  TCP [::1]:8080 (LISTEN)"
    ))
    #expect(l.count == 1)
    #expect(l[0].port == 8080)
    #expect(l[0].bind.family == .ipv6)
    #expect(l[0].bind.host == "::1")
}

@Test func wildcardBindsAreReachable() {
    let l = parseListeners(from: out(
        "postgres    512  pedro    7u  IPv4 0xdeadbeefcafef00d      0t0  TCP *:5432 (LISTEN)",
        "redis       513  pedro    6u  IPv4 0xfeed0000feed0000      0t0  TCP 0.0.0.0:6379 (LISTEN)",
        "app         514  pedro    9u  IPv6 0x0badc0de0badc0de      0t0  TCP [::]:9000 (LISTEN)"
    ))
    #expect(l.map(\.port) == [5432, 6379, 9000])
}

@Test func lanOnlyBindsDropped() {
    let l = parseListeners(from: out(
        "server      600  pedro    5u  IPv4 0x1111222233334444      0t0  TCP 192.168.1.20:5000 (LISTEN)",
        "server      601  pedro    5u  IPv4 0x5555666677778888      0t0  TCP 10.0.0.4:8080 (LISTEN)",
        "linklocal   602  pedro    5u  IPv6 0x9999aaaabbbbcccc      0t0  TCP [fe80::1%en0]:7000 (LISTEN)"
    ))
    #expect(l.isEmpty)
}

@Test func dualStackDedupe() {
    // same process, same port, on both loopback stacks -> one row
    let l = parseListeners(from: out(
        "vite      41231  pedro   23u  IPv4 0x1a2b3c4d5e6f7a8b      0t0  TCP 127.0.0.1:5173 (LISTEN)",
        "vite      41231  pedro   24u  IPv6 0x00aa11bb22cc33dd      0t0  TCP [::1]:5173 (LISTEN)"
    ))
    #expect(l.count == 1)
    #expect(l[0].port == 5173)
}

@Test func processNameWithSpaces() {
    let l = parseListeners(from: out(
        "Google Chrome  4242  pedro   50u  IPv4 0xabcabcabcabcabca      0t0  TCP 127.0.0.1:9222 (LISTEN)"
    ))
    #expect(l.count == 1)
    #expect(l[0].processName == "Google Chrome")
    #expect(l[0].pid == 4242)
    #expect(l[0].port == 9222)
    #expect(l[0].user == "pedro")
}

@Test func mixedRealisticOutputSortedByPort() {
    let l = parseListeners(from: out(
        "postgres    512  pedro    7u  IPv4 0xdeadbeefcafef00d      0t0  TCP *:5432 (LISTEN)",
        "node      41231  pedro   23u  IPv4 0x1a2b3c4d5e6f7a8b      0t0  TCP 127.0.0.1:3000 (LISTEN)",
        "server      600  root     5u  IPv4 0x1111222233334444      0t0  TCP 192.168.1.20:5000 (LISTEN)",
        "vite      41999  pedro   24u  IPv6 0x00aa11bb22cc33dd      0t0  TCP [::1]:5173 (LISTEN)"
    ))
    #expect(l.map(\.port) == [3000, 5173, 5432])
}

@Test func emptyAndGarbageInput() {
    #expect(parseListeners(from: "").isEmpty)
    #expect(parseListeners(from: "not a real lsof line").isEmpty)
    #expect(parseListeners(from: header).isEmpty)
}

// lsof is invoked with -iTCP so UDP shouldn't appear, but drop it if it leaks.
@Test func udpRowRejected() {
    let l = parseListeners(from: out(
        "dnsmasq     700  pedro    4u  IPv4 0x2222333344445555      0t0  UDP 127.0.0.1:53 (LISTEN)"
    ))
    #expect(l.isEmpty)
}

import Foundation

// Docker Desktop publishes every container port from one host process
// (`com.docker.backend`), so ten containers look like ten identical rows to
// `lsof` and `ps`. The host-port → container mapping only exists inside Docker.

/// The container behind a published host port.
public struct DockerContainer: Equatable {
    public let name: String
    public let image: String

    public init(name: String, image: String) {
        self.name = name
        self.image = image
    }
}

/// Parse Docker's `GET /containers/json` body into hostPort → container.
/// A container publishing the same port on IPv4 and IPv6 yields one entry.
public func parseDockerContainers(fromJSON json: String) -> [Int: DockerContainer] {
    guard let data = json.data(using: .utf8),
          let containers = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    else { return [:] }

    var byPort: [Int: DockerContainer] = [:]
    for container in containers {
        // Names are API-style with a leading slash: ["/damascus-postgres-1"]
        let rawName = (container["Names"] as? [String])?.first ?? ""
        let name = rawName.hasPrefix("/") ? String(rawName.dropFirst()) : rawName
        guard !name.isEmpty else { continue }
        let image = container["Image"] as? String ?? ""

        for port in container["Ports"] as? [[String: Any]] ?? [] {
            guard port["Type"] as? String == "tcp",
                  let hostPort = port["PublicPort"] as? Int
            else { continue }
            byPort[hostPort] = DockerContainer(name: name, image: image)
        }
    }
    return byPort
}

/// Published container ports, or empty when Docker isn't running.
///
/// Read over Docker's local unix socket with `curl` rather than the `docker`
/// CLI: a login-launched GUI app inherits a minimal PATH that doesn't include
/// `/usr/local/bin`, so `docker` would work in a terminal and silently fail in
/// the real app. `/usr/bin/curl` is always present.
// ponytail: spawning curl costs ~35ms per scan; swap for an NWConnection to the
// socket if it ever shows up in a profile.
func dockerContainers() async -> [Int: DockerContainer] {
    let candidates = [
        NSHomeDirectory() + "/.docker/run/docker.sock",   // Docker Desktop
        "/var/run/docker.sock",                           // colima, OrbStack, symlink
    ]
    guard let socket = candidates.first(where: { FileManager.default.fileExists(atPath: $0) })
    else { return [:] }

    let out = await Shell.run("/usr/bin/curl", [
        "-s", "--max-time", "2",
        "--unix-socket", socket,
        "http://localhost/containers/json",
    ])
    return parseDockerContainers(fromJSON: out)
}

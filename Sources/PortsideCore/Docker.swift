import Foundation

// Docker Desktop publishes every container port from one host process
// (`com.docker.backend`), so ten containers look like ten identical rows to
// `lsof` and `ps`. The host-port → container mapping only exists inside Docker.

/// The container behind a published host port.
public struct DockerContainer: Equatable {
    public let name: String
    public let image: String
    /// Compose's own view of the container, when it was started by compose:
    /// which stack, which service in it, and the directory the stack lives in.
    public let project: String?
    public let service: String?
    public let workingDir: String?

    public init(name: String, image: String,
                project: String? = nil, service: String? = nil, workingDir: String? = nil) {
        self.name = name
        self.image = image
        self.project = project
        self.service = service
        self.workingDir = workingDir
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
        let labels = container["Labels"] as? [String: String] ?? [:]

        for port in container["Ports"] as? [[String: Any]] ?? [] {
            guard port["Type"] as? String == "tcp",
                  let hostPort = port["PublicPort"] as? Int
            else { continue }
            byPort[hostPort] = DockerContainer(
                name: name, image: image,
                project: labels["com.docker.compose.project"],
                service: labels["com.docker.compose.service"],
                workingDir: labels["com.docker.compose.project.working_dir"]
            )
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

/// What a container row leads with.
///
/// `chennai-postgres-1` is compose's own construction — stack, service, replica
/// index — and the stack is named after a directory, so a renamed workspace
/// never appears in it. Compose labels carry the stack's directory, which maps
/// back to the workspace the user actually knows: `GMaps link/postgres`.
/// Containers started outside compose keep their own name.
public func dockerRowName(_ container: DockerContainer, workspaceNames: [String: String]) -> String {
    guard let service = container.service, !service.isEmpty else { return container.name }
    let workspace = container.workingDir
        .flatMap { conductorWorkspace(for: $0, names: workspaceNames)?.name }
    guard let stack = workspace ?? container.project, !stack.isEmpty else { return container.name }
    return "\(stack)/\(service)"
}

/// The directory to open for a container: where its compose file lives, but
/// stepping out of a hidden subdirectory — a stack kept in `<checkout>/.context`
/// should open the checkout, not the dotfolder. Nil when the container wasn't
/// started by compose, since the Docker helper's own storage is no use to anyone.
public func containerDirectory(_ container: DockerContainer) -> String? {
    guard let dir = container.workingDir, !dir.isEmpty else { return nil }
    let parts = dir.split(separator: "/").map(String.init)
    guard let leaf = parts.last, leaf.hasPrefix("."), parts.count > 1 else { return dir }
    return "/" + parts.dropLast().joined(separator: "/")
}

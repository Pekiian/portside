import Testing
@testable import PortsideCore

@Test func dockerPortMapping() {
    // shape of Docker's GET /containers/json, including the IPv4+IPv6 pair a
    // published port always comes in
    let json = """
    [{"Names":["/it-journal-test"],"Image":"postgres:16-alpine","Ports":[
      {"IP":"0.0.0.0","PrivatePort":5432,"PublicPort":5599,"Type":"tcp"},
      {"IP":"::","PrivatePort":5432,"PublicPort":5599,"Type":"tcp"}]},
     {"Names":["/wa-gateway-app"],"Image":"golang:1.25","Ports":[
      {"IP":"0.0.0.0","PrivatePort":8080,"PublicPort":8080,"Type":"tcp"}]}]
    """
    let map = parseDockerContainers(fromJSON: json)
    #expect(map.count == 2)
    #expect(map[5599] == DockerContainer(name: "it-journal-test", image: "postgres:16-alpine"))
    #expect(map[8080] == DockerContainer(name: "wa-gateway-app", image: "golang:1.25"))
    // the container port itself is not a host port
    #expect(map[5432] == nil)
}

@Test func dockerIgnoresUnpublishedAndUDP() {
    let json = """
    [{"Names":["/internal-only"],"Image":"redis:7-alpine","Ports":[
      {"PrivatePort":6379,"Type":"tcp"}]},
     {"Names":["/udp-thing"],"Image":"x","Ports":[
      {"IP":"0.0.0.0","PrivatePort":53,"PublicPort":9999,"Type":"udp"}]}]
    """
    #expect(parseDockerContainers(fromJSON: json).isEmpty)
}

@Test func dockerToleratesGarbage() {
    // Docker down, curl failed, socket returned an error page — all must be
    // empty maps, never a crash, so rows just keep their process-level name
    #expect(parseDockerContainers(fromJSON: "").isEmpty)
    #expect(parseDockerContainers(fromJSON: "not json").isEmpty)
    #expect(parseDockerContainers(fromJSON: #"{"message":"page not found"}"#).isEmpty)
    #expect(parseDockerContainers(fromJSON: #"[{"Names":[],"Ports":[]}]"#).isEmpty)
}

@Test func containerRowsLeadWithTheWorkspaceNotTheDirectory() {
    // compose builds "chennai-postgres-1" out of the stack directory, a service
    // and a replica index, so a renamed workspace never appears in it
    let json = """
    [{"Names":["/chennai-postgres-1"],"Image":"postgres:16",
      "Labels":{"com.docker.compose.project":"chennai","com.docker.compose.service":"postgres",
                "com.docker.compose.project.working_dir":"/Users/pedro/conductor/workspaces/core/chennai"},
      "Ports":[{"IP":"0.0.0.0","PrivatePort":5432,"PublicPort":5544,"Type":"tcp"}]},
     {"Names":["/wa-gateway-postgres"],"Image":"postgres:16-alpine",
      "Labels":{"com.docker.compose.project":"wa-gateway","com.docker.compose.service":"postgres",
                "com.docker.compose.project.working_dir":"/tmp/wa-gateway"},
      "Ports":[{"IP":"0.0.0.0","PrivatePort":5432,"PublicPort":5433,"Type":"tcp"}]},
     {"Names":["/one-off-eval"],"Image":"postgres:16-alpine","Labels":{},
      "Ports":[{"IP":"0.0.0.0","PrivatePort":5432,"PublicPort":55433,"Type":"tcp"}]}]
    """
    let map = parseDockerContainers(fromJSON: json)
    let names = ["/Users/pedro/conductor/workspaces/core/chennai": "GMaps link"]

    #expect(dockerRowName(map[5544]!, workspaceNames: names) == "GMaps link/postgres")
    // a stack outside any workspace still beats the container's own name
    #expect(dockerRowName(map[5433]!, workspaceNames: names) == "wa-gateway/postgres")
    // plain `docker run`, no compose labels: keep the container name
    #expect(dockerRowName(map[55433]!, workspaceNames: names) == "one-off-eval")
    // without Conductor the stack directory is the best available name
    #expect(dockerRowName(map[5544]!, workspaceNames: [:]) == "chennai/postgres")
}

@Test func containerDirectoryIsWhereTheStackLives() {
    func container(_ dir: String?) -> DockerContainer {
        DockerContainer(name: "c", image: "i", project: "p", service: "s", workingDir: dir)
    }
    #expect(containerDirectory(container("/Users/pedro/w/core/valencia")) == "/Users/pedro/w/core/valencia")
    // a stack kept in a dotfolder should open the checkout around it
    #expect(containerDirectory(container("/Users/pedro/w/core/port-louis/.context"))
            == "/Users/pedro/w/core/port-louis")
    // started with plain `docker run`: nowhere to open, so offer nothing
    #expect(containerDirectory(container(nil)) == nil)
    #expect(containerDirectory(container("")) == nil)
}

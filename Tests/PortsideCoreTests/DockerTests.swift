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

import Testing
import Foundation
@testable import PortsideCore

@Test func uptimeFormatting() {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    #expect(formatUptime(since: t0, now: t0.addingTimeInterval(45)) == "45s")
    #expect(formatUptime(since: t0, now: t0.addingTimeInterval(12 * 60)) == "12m")
    #expect(formatUptime(since: t0, now: t0.addingTimeInterval(2 * 3600 + 14 * 60)) == "2h 14m")
    #expect(formatUptime(since: t0, now: t0.addingTimeInterval(3 * 86400 + 4 * 3600)) == "3d 4h")
    #expect(formatUptime(since: t0, now: t0.addingTimeInterval(-10)) == "0s")
}

@Test func runtimeVsInterpreterOrder() {
    // Vite runs on node — must label Vite, not Node
    #expect(runtimeLabel(command: "/usr/bin/node /proj/node_modules/.bin/vite", processName: "node") == "Vite")
    #expect(runtimeLabel(command: "next-server (v14.1)", processName: "node") == "Next")
    #expect(runtimeLabel(command: "/usr/bin/node server.js", processName: "node") == "Node")
    #expect(runtimeLabel(command: "python -m uvicorn app:app", processName: "python") == "uvicorn")
    #expect(runtimeLabel(command: "puma 6.0 (tcp://127.0.0.1:3000)", processName: "ruby") == "Rails")
    #expect(runtimeLabel(command: "postgres: checkpointer", processName: "postgres") == "Postgres")
    #expect(runtimeLabel(command: "com.docker.backend proxy", processName: "docker") == "Docker")
    #expect(runtimeLabel(command: "/opt/some/random-binary", processName: "random-binary") == nil)
}

@Test func daemonFilter() {
    // known daemons by name (lsof-truncated too)
    #expect(isSystemDaemon(user: "pedro", execPath: "/usr/libexec/rapportd", processName: "rapportd"))
    #expect(isSystemDaemon(user: "pedro", execPath: "/System/…/ControlCenter", processName: "ControlCe"))
    // root under system dirs
    #expect(isSystemDaemon(user: "root", execPath: "/usr/sbin/cupsd", processName: "cupsd"))
    // user process is NEVER hidden, even if root would be
    #expect(!isSystemDaemon(user: "pedro", execPath: "/Users/pedro/.bin/node", processName: "node"))
    // root but not a system dir -> shown
    #expect(!isSystemDaemon(user: "root", execPath: "/Users/pedro/app", processName: "app"))
}

@Test func projectNaming() {
    #expect(parsePackageName(fromJSON: #"{"name":"my-blog","version":"1.0"}"#) == "my-blog")
    #expect(parsePackageName(fromJSON: "not json") == nil)
    #expect(parsePackageName(fromJSON: #"{"version":"1.0"}"#) == nil)

    // package.json name wins
    #expect(projectName(cwd: "/Users/pedro/code/blog", packageName: "my-blog", homeDir: "/Users/pedro") == "my-blog")
    // fall back to basename
    #expect(projectName(cwd: "/Users/pedro/code/blog", packageName: nil, homeDir: "/Users/pedro") == "blog")
    // throwaway dirs -> nil
    #expect(projectName(cwd: "/", packageName: nil, homeDir: "/Users/pedro") == nil)
    #expect(projectName(cwd: "/Users/pedro", packageName: nil, homeDir: "/Users/pedro") == nil)
    #expect(projectName(cwd: "/var/folders/xy/tmpabc", packageName: nil, homeDir: "/Users/pedro") == nil)
    #expect(projectName(cwd: nil, packageName: nil, homeDir: "/Users/pedro") == nil)
    // app-support storage -> nil: every Docker-mapped port sits in the same
    // container dir and would otherwise render as a row full of "Data"
    #expect(projectName(cwd: "/Users/pedro/Library/Containers/com.docker.docker/Data",
                        packageName: nil, homeDir: "/Users/pedro") == nil)
    #expect(projectName(cwd: "/Library/Application Support/thing",
                        packageName: nil, homeDir: "/Users/pedro") == nil)
    // a sibling whose name merely starts with "Library" is a real project
    #expect(projectName(cwd: "/Users/pedro/Library-notes",
                        packageName: nil, homeDir: "/Users/pedro") == "Library-notes")
}

@Test func workspaceLabels() {
    // two same-named projects in different folders become distinguishable
    #expect(workspaceLabel(cwd: "/Users/pedro/acme/storefront") == "…/acme/storefront")
    #expect(workspaceLabel(cwd: "/Users/pedro/beta/storefront") == "…/beta/storefront")
    // monorepo: structural dirs dropped so the workspace segment survives
    #expect(workspaceLabel(cwd: "/Users/pedro/conductor/workspaces/core/shanghai/apps/storefront") == "…/shanghai/storefront")
    #expect(workspaceLabel(cwd: "/Users/pedro/conductor/workspaces/core/munich/apps/storefront") == "…/munich/storefront")
    #expect(workspaceLabel(cwd: "/Users/pedro/conductor/workspaces/prota-landing/guangzhou") == "…/prota-landing/guangzhou")
    #expect(workspaceLabel(cwd: "/srv/app") == "/srv/app")
    #expect(workspaceLabel(cwd: "/only") == "/only")
    #expect(workspaceLabel(cwd: "/") == nil)
}

@Test func rowSubtitleNamesUnidentifiedProcesses() {
    func listener(_ process: String, project: String?, runtime: String?, cwd: String?,
                  detail: String? = nil) -> Listener {
        Listener(port: 1, pid: 42, processName: process, user: "pedro",
                 bind: BindAddress(raw: "127.0.0.1:1", typeToken: "IPv4")!,
                 cwd: cwd, projectName: project, runtime: runtime, detail: detail)
    }
    let workspace = "/Users/pedro/workspaces/core/san-diego"

    // adb and cloudflared both inherit a project's directory and are both titled
    // "san-diego" — the second line is the only thing telling them apart
    #expect(listener("adb", project: "san-diego", runtime: nil, cwd: workspace).subtitle
            == "adb · …/core/san-diego")
    #expect(listener("cloudflared", project: "san-diego", runtime: nil, cwd: workspace).subtitle
            == "cloudflared · …/core/san-diego")
    // a runtime pill already names the process, so it isn't repeated
    #expect(listener("node", project: "@repo/backend", runtime: "Node", cwd: "/Users/pedro/w/backend").subtitle
            == "…/w/backend")
    // a container's image outranks everything
    #expect(listener("com.docker.backend", project: "checkout-postgres", runtime: "Docker",
                     cwd: "/Users/pedro/Library/Containers/x", detail: "postgres:16-alpine").subtitle
            == "postgres:16-alpine")
    // when the title is already the process name, show the pid instead of it twice
    #expect(listener("lghub_agent", project: nil, runtime: nil, cwd: nil).subtitle == "pid 42")
}

@Test func directoryOnlyNamesRowsThatBelongToIt() {
    let home = "/Users/pedro"
    let workspace = "/Users/pedro/conductor/workspaces/core/san-diego"
    // adb and cloudflared merely started in this workspace — they must not
    // inherit its name, or two unrelated rows both read "san-diego"
    #expect(rowName(cwd: workspace, packageName: nil, runtime: nil, homeDir: home) == nil)
    // a recognised runtime is evidence the process is that project's server
    #expect(rowName(cwd: workspace, packageName: nil, runtime: "Node", homeDir: home) == "san-diego")
    // the checkout leads even when package.json names the project differently —
    // thirty worktrees of one repo all say "my-blog", only the directory differs
    #expect(rowName(cwd: "/Users/pedro/code/blog", packageName: "my-blog", runtime: nil, homeDir: home) == "blog")
    // with no usable directory, the package name is all there is
    #expect(rowName(cwd: "/tmp/scratch", packageName: "my-blog", runtime: nil, homeDir: home) == "my-blog")
    // the throwaway-directory rules still apply on top
    #expect(rowName(cwd: "/", packageName: nil, runtime: "Node", homeDir: home) == nil)
}

@Test func checkoutNamesDistinguishParallelWorktrees() {
    let core = "/Users/pedro/conductor/workspaces/core"
    // the workspace segment is the only thing that differs between 37 checkouts
    #expect(checkoutName(cwd: core + "/san-diego") == "san-diego")
    #expect(checkoutName(cwd: core + "/damascus") == "damascus")
    // inside a monorepo, "storefront" alone is identical in all of them
    #expect(checkoutName(cwd: core + "/san-diego/apps/storefront") == "san-diego/storefront")
    #expect(checkoutName(cwd: core + "/damascus/packages/api") == "damascus/api")
    // ordinary projects keep their own name
    #expect(checkoutName(cwd: "/Users/pedro/code/blog") == "blog")
    // a structural dir is never the whole name
    #expect(checkoutName(cwd: "/Users/pedro/proj/src") == "proj")
    #expect(checkoutName(cwd: "/srv") == "srv")
    #expect(checkoutName(cwd: "/") == nil)
}

@Test func renamedConductorWorkspacesUseTheirDisplayName() {
    // Conductor renames a workspace in its own database and never touches the
    // directory, so the folder stays `warsaw` for a workspace called "Marketing"
    let rows = "/Users/pedro/conductor/workspaces/core/warsaw\tMarketing\n"
             + "/Users/pedro/conductor/workspaces/Black Pearl Ventures/davis\tPearl Work\n"
             + "malformed-line-with-no-tab\n"
    let names = parseConductorWorkspaces(rows)
    #expect(names.count == 2)
    // paths and names both contain spaces, so only the first tab splits
    #expect(names["/Users/pedro/conductor/workspaces/Black Pearl Ventures/davis"] == "Pearl Work")

    #expect(checkoutName(cwd: "/Users/pedro/conductor/workspaces/core/warsaw", workspaceNames: names) == "Marketing")
    #expect(checkoutName(cwd: "/Users/pedro/conductor/workspaces/core/warsaw/apps/storefront",
                         workspaceNames: names) == "Marketing/storefront")
    // never renamed, or no Conductor at all: the directory name stands
    #expect(checkoutName(cwd: "/Users/pedro/conductor/workspaces/Personal/quito", workspaceNames: names) == "quito")
    #expect(checkoutName(cwd: "/Users/pedro/code/blog", workspaceNames: [:]) == "blog")
    // a sibling that merely shares a prefix is not inside the workspace
    #expect(checkoutName(cwd: "/Users/pedro/conductor/workspaces/core/warsaw-old",
                         workspaceNames: names) == "warsaw-old")
}

@Test func backgroundAppsHaveNoWorkingDirectory() {
    let home = "/Users/pedro"
    // Finder and launchd hand a GUI app `/`; a dev server inherits its checkout
    #expect(isBackgroundApp(cwd: "/", hasContainer: false, homeDir: home))
    #expect(isBackgroundApp(cwd: nil, hasContainer: false, homeDir: home))
    #expect(isBackgroundApp(cwd: home, hasContainer: false, homeDir: home))
    #expect(!isBackgroundApp(cwd: home + "/conductor/workspaces/core/warsaw",
                             hasContainer: false, homeDir: home))
    // Docker's helper has no useful cwd, but a container port is the user's work
    #expect(!isBackgroundApp(cwd: home + "/Library/Containers/com.docker.docker/Data",
                             hasContainer: true, homeDir: home))
    #expect(isBackgroundApp(cwd: home + "/Library/Containers/com.docker.docker/Data",
                            hasContainer: false, homeDir: home))
}

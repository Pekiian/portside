import Foundation
import SwiftUI
import AppKit
import Combine
import UserNotifications
import ServiceManagement
import PortsideCore

/// One displayed row: a live listener, or a placeholder for a pinned or
/// sectioned port that isn't currently listening.
struct PortRow: Identifiable, Equatable {
    let port: Int
    var listener: Listener?
    var label: String?
    var pinned: Bool
    /// User-made section this port lives in; nil = the main list.
    var section: String?
    var statusMessage: String?

    var id: Int { port }
    var isListening: Bool { listener != nil }
    /// Not something the user is working on — sorted below their own ports.
    var isBackgroundApp: Bool { listener?.isBackgroundApp ?? false }
    var url: URL? { URL(string: "http://localhost:\(port)") }

    /// Primary name: custom label > project > process, or "(down)" placeholder.
    var title: String {
        if let label { return label }
        return listener?.displayName ?? "port \(port)"
    }
}

/// A group stop waiting for the user to confirm it in the popover.
struct PendingStop {
    let name: String
    let rows: [PortRow]
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var rows: [PortRow] = []

    @Published var isMenuOpen = false {
        didSet {
            restartPolling()
            if !isMenuOpen { pendingStop = nil }   // closing the popover cancels
        }
    }
    @Published var pendingStop: PendingStop?

    let prefs = Preferences()
    private let scanner = PortScanner()

    private var pollTask: Task<Void, Never>?
    private var isAsleep = false
    private var lastActivePins: Set<Int> = []

    /// Badge = ports listening in the main list. Ports filed into a section are
    /// ones the user set aside, so they don't add to the count.
    var badgeCount: Int { rows.filter { $0.isListening && $0.section == nil }.count }

    init() {
        observeSleepWake()
        applyLaunchAtLogin(prefs.launchAtLogin)
        prefs.$launchAtLogin
            .dropFirst()
            .sink { [weak self] in self?.applyLaunchAtLogin($0) }
            .store(in: &cancellables)
        // rebuild rows when labels/pins/showSystem change without waiting for poll
        prefs.$labels.dropFirst().sink { [weak self] _ in self?.refreshNow() }.store(in: &cancellables)
        prefs.$pinnedPorts.dropFirst().sink { [weak self] _ in self?.refreshNow() }.store(in: &cancellables)
        prefs.$sectionByPort.dropFirst().sink { [weak self] _ in self?.refreshNow() }.store(in: &cancellables)
        prefs.$showSystem.dropFirst().sink { [weak self] _ in self?.refreshNow() }.store(in: &cancellables)
        prefs.$showBackgroundApps.dropFirst().sink { [weak self] _ in self?.refreshNow() }.store(in: &cancellables)

        restartPolling()
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: polling

    private func restartPolling() {
        pollTask?.cancel()
        let interval: UInt64 = isMenuOpen ? 2 : 15
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !self.isAsleep { await self.tick() }
                try? await Task.sleep(nanoseconds: interval * 1_000_000_000)
            }
        }
    }

    func refreshNow() { Task { await tick() } }

    private func tick() async {
        let listeners = await scanner.scan(showSystem: prefs.showSystem)
        let newRows = buildRows(from: listeners)
        notifyPinnedStops(newRows)
        // in-place mutation of the identified array → SwiftUI animates ins/rm
        withAnimation(.easeInOut(duration: 0.18)) { self.rows = newRows }
    }

    // MARK: row assembly (pins to top, placeholders for down pins/sectioned ports)

    private func buildRows(from listeners: [Listener]) -> [PortRow] {
        let activePorts = Set(listeners.map(\.port))

        var rows: [PortRow] = listeners.map { l in
            PortRow(
                port: l.port,
                listener: l,
                label: prefs.label(for: l.port),
                pinned: prefs.isPinned(l.port),
                section: prefs.section(for: l.port),
                statusMessage: statusByPort[l.port]
            )
        }
        // placeholder rows for pinned or sectioned ports that are down, so you
        // see the app you filed away has stopped instead of it vanishing
        let kept = prefs.pinnedPorts.union(prefs.sectionByPort.keys)
        for port in kept where !activePorts.contains(port) {
            rows.append(PortRow(
                port: port,
                listener: nil,
                label: prefs.label(for: port),
                pinned: prefs.isPinned(port),
                section: prefs.section(for: port),
                statusMessage: statusByPort[port]
            ))
        }
        if !prefs.showBackgroundApps {
            rows.removeAll { $0.isBackgroundApp && !$0.pinned && $0.section == nil }
        }
        // your own ports first, pinned above those, background apps last
        return rows.sorted {
            if $0.pinned != $1.pinned { return $0.pinned && !$1.pinned }
            if $0.isBackgroundApp != $1.isBackgroundApp { return !$0.isBackgroundApp }
            return $0.port < $1.port
        }
    }

    // MARK: pinned-stop notifications

    private func notifyPinnedStops(_ newRows: [PortRow]) {
        let activePins = Set(newRows.filter { $0.pinned && $0.isListening }.map(\.port))
        defer { lastActivePins = activePins }
        guard prefs.notifyOnStopPinned else { return }
        let stopped = lastActivePins.subtracting(activePins)
        for port in stopped {
            let label = prefs.label(for: port) ?? "localhost:\(port)"
            postNotification(title: "Pinned port stopped", body: "\(label) (:\(port)) is no longer listening.")
        }
    }

    // MARK: row actions

    private var statusByPort: [Int: String] = [:]

    func open(_ row: PortRow) {
        guard let url = row.url else { return }
        NSWorkspace.shared.open(url)
    }

    func copyURL(_ row: PortRow) {
        guard let url = row.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        flash(row.port, "Copied", clearAfter: 1.5)
    }

    func openTerminal(_ row: PortRow) {
        guard let cwd = row.listener?.cwd else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-a", "Terminal", cwd]
        try? p.run()
    }

    func revealInFinder(_ row: PortRow) {
        guard let cwd = row.listener?.cwd else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: cwd)
    }

    func kill(_ row: PortRow, force: Bool) {
        guard let listener = row.listener else { return }
        flash(row.port, force ? "Force killing…" : "Stopping…")
        Task {
            report(row.port, await Self.stop(listener, force: force))
            await tick()
        }
    }

    /// A container goes through Docker; anything else gets signalled.
    nonisolated private static func stop(_ l: Listener, force: Bool) async -> KillOutcome {
        if let id = l.containerID { return await stopContainer(id: id, force: force) }
        // a Docker port whose container wasn't found: its pid is Docker itself
        if l.runtime == "Docker" { return .failed("container not found") }
        return await ProcessControl.kill(pid: l.pid, force: force)
    }

    private func report(_ port: Int, _ outcome: KillOutcome) {
        switch outcome {
        case .terminated: flash(port, "Stopped", clearAfter: 2)
        case .forced: flash(port, "Force killed", clearAfter: 2)
        case .failed(let msg): flash(port, "Failed: \(msg)", clearAfter: 4)
        }
    }

    // MARK: stop a whole group

    /// Every listening port from the same repository as `row`, minus the ones
    /// filed into a section: those were set aside as not-development.
    func workspaceRows(of row: PortRow) -> [PortRow] {
        guard let path = row.listener?.workspacePath else { return [] }
        return rows.filter { $0.isListening && $0.section == nil && $0.listener?.workspacePath == path }
    }

    func sectionRows(_ name: String) -> [PortRow] {
        rows.filter { $0.isListening && $0.section == name }
    }

    /// Asks first, in the popover; `confirmPendingStop` does the stopping.
    func stopAll(_ rows: [PortRow], in name: String) {
        guard !rows.isEmpty else { return }
        withAnimation(.panel) { pendingStop = PendingStop(name: name, rows: rows) }
    }

    func cancelPendingStop() {
        withAnimation(.panel) { pendingStop = nil }
    }

    /// Stops them all at once. A process listening on several ports, or a
    /// container publishing several, is stopped once.
    func confirmPendingStop() {
        guard let rows = pendingStop?.rows else { return }
        withAnimation(.panel) { pendingStop = nil }
        var portsByTarget: [String: [Int]] = [:]
        var targets: [String: Listener] = [:]
        for row in rows {
            guard let l = row.listener else { continue }
            let key = l.containerID ?? "pid:\(l.pid)"
            portsByTarget[key, default: []].append(row.port)
            targets[key] = l
            flash(row.port, "Stopping…")
        }
        Task {
            await withTaskGroup(of: (String, KillOutcome).self) { group in
                for (key, l) in targets { group.addTask { (key, await Self.stop(l, force: false)) } }
                for await (key, outcome) in group {
                    for port in portsByTarget[key] ?? [] { report(port, outcome) }
                }
            }
            await tick()
        }
    }

    private func flash(_ port: Int, _ message: String, clearAfter seconds: Double = 0) {
        statusByPort[port] = message
        if let i = rows.firstIndex(where: { $0.port == port }) { rows[i].statusMessage = message }
        if seconds > 0 {
            Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                statusByPort[port] = nil
                if let i = rows.firstIndex(where: { $0.port == port }) { rows[i].statusMessage = nil }
            }
        }
    }

    // MARK: sleep / wake gating

    private func observeSleepWake() {
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isAsleep = true }
            }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.isAsleep = false
                    self?.refreshNow()
                }
            }
        }
    }

    // MARK: launch at login + notifications

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Portside: launch-at-login toggle failed: \(error)")
        }
    }

    func requestNotificationAuthIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func postNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}

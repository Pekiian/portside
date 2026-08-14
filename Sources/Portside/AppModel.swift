import Foundation
import SwiftUI
import AppKit
import Combine
import UserNotifications
import ServiceManagement
import PortsideCore

/// One displayed row: a live listener, or a pinned placeholder when its port
/// isn't currently listening.
struct PortRow: Identifiable, Equatable {
    let port: Int
    var listener: Listener?
    var label: String?
    var pinned: Bool
    var statusMessage: String?

    var id: Int { port }
    var isListening: Bool { listener != nil }
    var url: URL? { URL(string: "http://localhost:\(port)") }

    /// Primary name: custom label > project > process, or "(down)" placeholder.
    var title: String {
        if let label { return label }
        return listener?.displayName ?? "port \(port)"
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var rows: [PortRow] = []
    @Published var isMenuOpen = false { didSet { restartPolling() } }

    let prefs = Preferences()
    private let scanner = PortScanner()

    private var pollTask: Task<Void, Never>?
    private var isAsleep = false
    private var lastActivePins: Set<Int> = []

    /// Badge = distinct localhost ports currently listening.
    var badgeCount: Int { rows.filter { $0.isListening }.count }

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
        prefs.$showSystem.dropFirst().sink { [weak self] _ in self?.refreshNow() }.store(in: &cancellables)

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

    // MARK: row assembly (pins to top, placeholders for down pins)

    private func buildRows(from listeners: [Listener]) -> [PortRow] {
        let activePorts = Set(listeners.map(\.port))

        var rows: [PortRow] = listeners.map { l in
            PortRow(
                port: l.port,
                listener: l,
                label: prefs.label(for: l.port),
                pinned: prefs.isPinned(l.port),
                statusMessage: statusByPort[l.port]
            )
        }
        // placeholder rows for pinned-but-down ports
        for port in prefs.pinnedPorts where !activePorts.contains(port) {
            rows.append(PortRow(
                port: port,
                listener: nil,
                label: prefs.label(for: port),
                pinned: true,
                statusMessage: statusByPort[port]
            ))
        }
        // pinned first, then by port asc
        return rows.sorted {
            if $0.pinned != $1.pinned { return $0.pinned && !$1.pinned }
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
        flash(row.port, "Copied")
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
        guard let pid = row.listener?.pid else { return }
        flash(row.port, force ? "Force killing…" : "Stopping…")
        Task {
            let outcome = await ProcessControl.kill(pid: pid, force: force)
            switch outcome {
            case .terminated: flash(row.port, "Stopped", clearAfter: 2)
            case .forced: flash(row.port, "Force killed", clearAfter: 2)
            case .failed(let msg): flash(row.port, "Failed: \(msg)", clearAfter: 4)
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

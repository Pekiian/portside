import Foundation
import Combine

/// UserDefaults-backed settings, custom labels, and pins. That's the whole
/// persistence story — no database, no files.
final class Preferences: ObservableObject {
    private let defaults = UserDefaults.standard

    private enum Key {
        static let labels = "customLabels"        // [portString: label]
        static let pins = "pinnedPorts"           // [Int]
        static let showSystem = "showSystemProcesses"
        static let showBackground = "showBackgroundApps"
        static let launchAtLogin = "launchAtLogin"
        static let notifyPinned = "notifyOnStopPinned"
    }

    @Published var showSystem: Bool {
        didSet { defaults.set(showSystem, forKey: Key.showSystem) }
    }
    @Published var showBackgroundApps: Bool {
        didSet { defaults.set(showBackgroundApps, forKey: Key.showBackground) }
    }
    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }
    @Published var notifyOnStopPinned: Bool {
        didSet { defaults.set(notifyOnStopPinned, forKey: Key.notifyPinned) }
    }
    @Published private(set) var labels: [Int: String]
    @Published private(set) var pinnedPorts: Set<Int>

    init() {
        showSystem = defaults.bool(forKey: Key.showSystem)
        // shown by default: grouping already keeps them out of the way
        showBackgroundApps = defaults.object(forKey: Key.showBackground) as? Bool ?? true
        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        notifyOnStopPinned = defaults.bool(forKey: Key.notifyPinned)

        let rawLabels = defaults.dictionary(forKey: Key.labels) as? [String: String] ?? [:]
        labels = Dictionary(uniqueKeysWithValues: rawLabels.compactMap { key, value in
            Int(key).map { ($0, value) }
        })
        pinnedPorts = Set((defaults.array(forKey: Key.pins) as? [Int]) ?? [])
    }

    func label(for port: Int) -> String? { labels[port] }

    func setLabel(_ label: String?, for port: Int) {
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            labels[port] = trimmed
        } else {
            labels[port] = nil
        }
        defaults.set(
            Dictionary(uniqueKeysWithValues: labels.map { (String($0.key), $0.value) }),
            forKey: Key.labels
        )
    }

    func isPinned(_ port: Int) -> Bool { pinnedPorts.contains(port) }

    func togglePin(_ port: Int) {
        if pinnedPorts.contains(port) { pinnedPorts.remove(port) }
        else { pinnedPorts.insert(port) }
        defaults.set(Array(pinnedPorts), forKey: Key.pins)
    }
}

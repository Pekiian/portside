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
        static let sections = "sections"              // [String], in display order
        static let sectionByPort = "sectionByPort"    // [portString: section name]
        static let collapsed = "collapsedSections"    // [String]
        static let backgroundCollapsed = "backgroundCollapsed"
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
    /// Sections the user made, in the order they're shown.
    @Published private(set) var sections: [String]
    @Published private(set) var sectionByPort: [Int: String]
    @Published private(set) var collapsedSections: Set<String>
    @Published var backgroundCollapsed: Bool {
        didSet { defaults.set(backgroundCollapsed, forKey: Key.backgroundCollapsed) }
    }

    init() {
        showSystem = defaults.bool(forKey: Key.showSystem)
        // shown by default: grouping already keeps them out of the way
        showBackgroundApps = defaults.object(forKey: Key.showBackground) as? Bool ?? true
        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        notifyOnStopPinned = defaults.bool(forKey: Key.notifyPinned)

        labels = Self.portKeyed(defaults.dictionary(forKey: Key.labels))
        pinnedPorts = Set((defaults.array(forKey: Key.pins) as? [Int]) ?? [])
        sections = defaults.stringArray(forKey: Key.sections) ?? []
        sectionByPort = Self.portKeyed(defaults.dictionary(forKey: Key.sectionByPort))
        collapsedSections = Set(defaults.stringArray(forKey: Key.collapsed) ?? [])
        backgroundCollapsed = defaults.bool(forKey: Key.backgroundCollapsed)
    }

    /// UserDefaults only takes string keys, so port maps are stored as "3000": value.
    private static func portKeyed(_ raw: [String: Any]?) -> [Int: String] {
        let raw = raw as? [String: String] ?? [:]
        return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
            Int(key).map { ($0, value) }
        })
    }
    private func save(_ map: [Int: String], _ key: String) {
        defaults.set(Dictionary(uniqueKeysWithValues: map.map { (String($0.key), $0.value) }), forKey: key)
    }

    func label(for port: Int) -> String? { labels[port] }

    func setLabel(_ label: String?, for port: Int) {
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            labels[port] = trimmed
        } else {
            labels[port] = nil
        }
        save(labels, Key.labels)
    }

    func isPinned(_ port: Int) -> Bool { pinnedPorts.contains(port) }

    func togglePin(_ port: Int) {
        if pinnedPorts.contains(port) { pinnedPorts.remove(port) }
        else { pinnedPorts.insert(port) }
        defaults.set(Array(pinnedPorts), forKey: Key.pins)
    }

    // MARK: sections

    func section(for port: Int) -> String? { sectionByPort[port] }

    /// nil takes the port back to the main list.
    func setSection(_ name: String?, for port: Int) {
        sectionByPort[port] = name
        save(sectionByPort, Key.sectionByPort)
    }

    /// Appends a section, numbering the name if it's taken. Returns the name used.
    @discardableResult
    func addSection(_ base: String = "New Section") -> String {
        var name = base
        var n = 2
        while sections.contains(name) { name = "\(base) \(n)"; n += 1 }
        sections.append(name)
        saveSections()
        return name
    }

    /// Ignored when the new name is blank or already used by another section.
    func renameSection(_ old: String, to new: String) {
        let new = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !new.isEmpty, !sections.contains(new),
              let i = sections.firstIndex(of: old) else { return }
        sections[i] = new
        for (port, name) in sectionByPort where name == old { sectionByPort[port] = new }
        if collapsedSections.remove(old) != nil { collapsedSections.insert(new) }
        saveSections()
    }

    /// Its ports go back to the main list.
    func deleteSection(_ name: String) {
        sections.removeAll { $0 == name }
        sectionByPort = sectionByPort.filter { $0.value != name }
        collapsedSections.remove(name)
        saveSections()
    }

    /// Drop `name` on `target`: it takes target's slot, so dragging down lands
    /// below the target and dragging up lands above it.
    func moveSection(_ name: String, onto target: String) {
        guard name != target,
              let from = sections.firstIndex(of: name),
              let to = sections.firstIndex(of: target) else { return }
        sections.remove(at: from)
        sections.insert(name, at: to)
        saveSections()
    }

    func toggleCollapsed(_ name: String) {
        if collapsedSections.remove(name) == nil { collapsedSections.insert(name) }
        defaults.set(Array(collapsedSections), forKey: Key.collapsed)
    }

    private func saveSections() {
        defaults.set(sections, forKey: Key.sections)
        save(sectionByPort, Key.sectionByPort)
        defaults.set(Array(collapsedSections), forKey: Key.collapsed)
    }
}

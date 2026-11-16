import SwiftUI
import AppKit
import PortsideCore

// MARK: - Popover content

struct MenuContentView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var prefs: Preferences
    @State private var showSettings = false
    @State private var editingPort: Int?
    @State private var draft = ""
    @State private var editingSection: String?
    @State private var sectionDraft = ""
    @State private var mainTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if showSettings {
                SettingsPanel()
            } else if model.rows.isEmpty && prefs.sections.isEmpty {
                EmptyStateView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // your ports, then your sections in your order, then background apps
                        rowList(mainRows)
                        ForEach(prefs.sections, id: \.self) { name in
                            let rows = model.rows.filter { $0.section == name }
                            let collapsed = prefs.collapsedSections.contains(name)
                            UserSectionHeader(
                                name: name,
                                listening: rows.filter(\.isListening).count,
                                collapsed: collapsed,
                                isEditing: editingSection == name,
                                draft: $sectionDraft,
                                onBeginRename: { sectionDraft = name; editingSection = name },
                                onCommit: commitSectionRename,
                                onCancel: { editingSection = nil },
                                onDrop: { drop($0, on: name) }
                            )
                            if !collapsed { rowList(rows) }
                        }
                        if !backgroundRows.isEmpty {
                            SectionHeading(
                                text: "Background apps",
                                count: backgroundRows.count,
                                collapsed: prefs.backgroundCollapsed,
                                onToggle: { withAnimation(.fold) { prefs.backgroundCollapsed.toggle() } }
                            )
                            if !prefs.backgroundCollapsed { rowList(backgroundRows) }
                        }
                    }
                }
                // ScrollView has no intrinsic height in a content-sized window;
                // size it to the content, capped so the whole popover stays ~500pt.
                .frame(height: min(listHeight, 400))
            }
            Divider()
            footer
        }
        .frame(width: 380)
    }

    private var header: some View {
        HStack {
            Text("Localhost")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text(verbatim: "\(model.badgeCount) listening")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
        // dropping a row here takes it out of its section
        .background(mainTargeted ? Color.accentColor.opacity(0.15) : .clear)
        .dropDestination(for: String.self) { items, _ in drop(items, on: nil) } isTargeted: { mainTargeted = $0 }
    }

    // MARK: grouping

    private var mainRows: [PortRow] { model.rows.filter { $0.section == nil && !$0.isBackgroundApp } }
    private var backgroundRows: [PortRow] { model.rows.filter { $0.section == nil && $0.isBackgroundApp } }

    private var listHeight: CGFloat {
        let visibleRows = model.rows.filter { row in
            if let s = row.section { return !prefs.collapsedSections.contains(s) }
            return !(row.isBackgroundApp && prefs.backgroundCollapsed)
        }.count
        let headings = prefs.sections.count + (backgroundRows.isEmpty ? 0 : 1)
        return CGFloat(visibleRows) * 48 + CGFloat(headings) * 30
    }

    @ViewBuilder private func rowList(_ rows: [PortRow]) -> some View {
        ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
            if i > 0 { Divider().opacity(0.4) }
            ListenerRow(
                row: row,
                isEditing: editingPort == row.port,
                draft: $draft,
                onBeginRename: { beginRename(row) },
                onCommit: commitRename,
                onCancel: { editingPort = nil },
                onNewSection: { newSection(for: row.port) }
            )
            .draggable(DragItem.port(row.port))
        }
    }

    // MARK: sections

    /// A row dropped on a section moves into it (nil = main list); a section
    /// header dropped on another reorders them.
    private func drop(_ items: [String], on section: String?) -> Bool {
        for item in items {
            if let port = DragItem.port(from: item) {
                prefs.setSection(section, for: port)
            } else if let moved = DragItem.section(from: item), let section {
                prefs.moveSection(moved, onto: section)
            }
        }
        return true
    }

    private func newSection(for port: Int) {
        let name = prefs.addSection()
        prefs.setSection(name, for: port)
        sectionDraft = name
        editingSection = name     // name it right away
    }

    private func commitSectionRename() {
        guard let old = editingSection else { return }
        prefs.renameSection(old, to: sectionDraft)
        editingSection = nil
    }

    private var footer: some View {
        HStack {
            Button {
                showSettings.toggle()
            } label: {
                Label(showSettings ? "Back" : "Settings",
                      systemImage: showSettings ? "chevron.left" : "gearshape")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(showSettings ? Color.accentColor : .secondary)
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Quit").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: inline rename

    private func beginRename(_ row: PortRow) {
        draft = model.prefs.label(for: row.port) ?? ""
        editingPort = row.port
    }
    private func commitRename() {
        guard let port = editingPort else { return }
        model.prefs.setLabel(draft, for: port)   // empty clears the label
        editingPort = nil
    }
}

// MARK: - Row

struct ListenerRow: View {
    let row: PortRow
    var isEditing: Bool
    @Binding var draft: String
    var onBeginRename: () -> Void
    var onCommit: () -> Void
    var onCancel: () -> Void
    var onNewSection: () -> Void
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var prefs: Preferences
    @State private var hovering = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: ":" + String(row.port))
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(row.isListening ? .primary : .secondary)
                .frame(width: 56, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if isEditing {
                        TextField("Label", text: $draft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .focused($fieldFocused)
                            .onSubmit(onCommit)
                            .onExitCommand(perform: onCancel)      // Esc cancels
                            .onAppear { fieldFocused = true }
                            // clicking away ends the rename, as it does in Finder —
                            // without this the row stays in edit mode for good
                            .onChange(of: fieldFocused) { _, focused in
                                if !focused { onCommit() }
                            }
                    } else {
                        Text(row.title)
                            .font(.system(size: 13))
                            .lineLimit(1)
                            .foregroundStyle(row.isListening ? .primary : .secondary)
                    }
                    if row.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    if let runtime = row.listener?.runtime {
                        RuntimePill(text: runtime)
                    }
                    if let bind = row.listener?.bind, bind.isWildcard {
                        LANPill()
                            .help("Bound to \(bind.host):\(row.port) — reachable from your network, not only this Mac")
                    }
                }
                secondaryLine
            }

            Spacer(minLength: 4)

            if hovering, row.isListening {
                Button { model.kill(row, force: false) } label: {
                    Image(systemName: "stop.circle").font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .help("Kill (SIGTERM, then SIGKILL after 3s)")

                Button { model.copyURL(row) } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Copy http://localhost:\(row.port)")
            } else if let uptime = uptimeText {
                Text(uptime)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .background(hovering ? Color.primary.opacity(0.06) : .clear)
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { onBeginRename() }
        .onTapGesture { handleTap() }
        .contextMenu { contextMenu }
    }

    @ViewBuilder private var secondaryLine: some View {
        if let message = row.statusMessage {
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.orange)
        } else if let l = row.listener {
            // container image, workspace path, or the process name when
            // nothing else has named the row. Full detail on hover.
            Text(verbatim: l.subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.head)
                .help("\(l.cwd ?? "")\n\(l.processName) · \(l.pid)")
        } else {
            Text("not listening")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
    }

    private var uptimeText: String? {
        guard let started = row.listener?.startedAt else { return nil }
        return formatUptime(since: started)
    }

    private func handleTap() {
        guard !isEditing else { return }   // don't hijack clicks in the text field
        guard row.isListening else { return }
        if NSEvent.modifierFlags.contains(.command) {
            model.copyURL(row)
        } else {
            model.open(row)
        }
    }

    @ViewBuilder private var contextMenu: some View {
        if row.isListening {
            Button("Open in Browser") { model.open(row) }
            Button("Copy URL") { model.copyURL(row) }
            if let cwd = row.listener?.cwd {
                Button("Open cwd in Terminal") { model.openTerminal(row) }
                Button("Reveal cwd in Finder") { model.revealInFinder(row) }
                if !Editors.installed.isEmpty {
                    Menu("Open cwd in") {
                        ForEach(Editors.installed) { editor in
                            Button(editor.name) { Editors.open(cwd, in: editor) }
                        }
                    }
                }
            }
        }
        Button(prefs.isPinned(row.port) ? "Unpin" : "Pin") {
            prefs.togglePin(row.port)
        }
        Button("Rename", action: onBeginRename)
        Menu("Move to Section") {
            ForEach(prefs.sections, id: \.self) { name in
                Button(name) { prefs.setSection(name, for: row.port) }
                    .disabled(name == row.section)
            }
            if !prefs.sections.isEmpty { Divider() }
            Button("New Section…", action: onNewSection)
            if row.section != nil {
                Button("Back to Main List") { prefs.setSection(nil, for: row.port) }
            }
        }
        if row.isListening {
            Divider()
            Button("Kill") { model.kill(row, force: false) }
            Button("Force Kill", role: .destructive) { model.kill(row, force: true) }
        }
    }
}

/// Drag payloads. Plain strings with a prefix, so one drop target can tell a
/// dragged row from a dragged section header.
enum DragItem {
    static func port(_ port: Int) -> String { "port:\(port)" }
    static func section(_ name: String) -> String { "section:\(name)" }
    static func port(from item: String) -> Int? {
        item.hasPrefix("port:") ? Int(item.dropFirst(5)) : nil
    }
    static func section(from item: String) -> String? {
        item.hasPrefix("section:") ? String(item.dropFirst(8)) : nil
    }
}

/// Heading of a section the user made: click to fold, drag to reorder, drop
/// rows on it to file them, right-click to rename or delete.
struct UserSectionHeader: View {
    let name: String
    let listening: Int
    let collapsed: Bool
    var isEditing: Bool
    @Binding var draft: String
    var onBeginRename: () -> Void
    var onCommit: () -> Void
    var onCancel: () -> Void
    var onDrop: ([String]) -> Bool
    @EnvironmentObject var prefs: Preferences
    @State private var targeted = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 5) {
            FoldChevron(collapsed: collapsed)
            if isEditing {
                TextField("Section name", text: $draft)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.primary)
                    .focused($fieldFocused)
                    .onSubmit(onCommit)
                    .onExitCommand(perform: onCancel)
                    .onAppear { fieldFocused = true }
                    .onChange(of: fieldFocused) { _, focused in
                        if !focused { onCommit() }
                    }
            } else {
                Text(name)
            }
            Spacer()
            if listening > 0 {
                Text(verbatim: String(listening)).monospacedDigit()
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .contentShape(Rectangle())
        .background(targeted ? Color.accentColor.opacity(0.15) : .clear)
        .onTapGesture {
            if !isEditing { withAnimation(.fold) { prefs.toggleCollapsed(name) } }
        }
        .contextMenu {
            Button("Rename", action: onBeginRename)
            Button("Delete Section", role: .destructive) { prefs.deleteSection(name) }
        }
        .draggable(DragItem.section(name))
        .dropDestination(for: String.self) { items, _ in onDrop(items) } isTargeted: { targeted = $0 }
    }
}

/// Divides the user's own ports from everything else in the list. Click to fold.
struct SectionHeading: View {
    let text: String
    let count: Int
    let collapsed: Bool
    var onToggle: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            FoldChevron(collapsed: collapsed)
            Text(text)
            Spacer()
            Text(verbatim: String(count)).monospacedDigit()
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
    }
}

struct FoldChevron: View {
    let collapsed: Bool
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .bold))
            .rotationEffect(.degrees(collapsed ? 0 : 90))
    }
}

extension Animation {
    /// Opening and folding a section: rows fade, the list height and chevron follow.
    static let fold = Animation.easeInOut(duration: 0.22)
}

/// Bound to every interface, so the port answers on this Mac's network address
/// too. Outlined rather than filled so it reads as a note about the row instead
/// of a second runtime tag.
struct LANPill: View {
    var body: some View {
        Text("LAN")
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.45), lineWidth: 1))
            .foregroundStyle(.secondary)
    }
}

struct RuntimePill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Self.tint(for: text), in: Capsule())
            // the label carries the meaning; colour only speeds recognition, so
            // the text stays at full contrast in both appearances
            .foregroundStyle(.primary)
    }

    /// Brand colour per runtime, as a wash behind the label. Brands that are
    /// black-and-white (Next, Deno, Remix, Flask) get the neutral fill — a
    /// literal black pill vanishes in dark mode. Webpack and Postgres use
    /// adjusted tones: their own blues are too pale on light and too dark on
    /// dark respectively.
    private static func tint(for runtime: String) -> Color {
        guard let hex = brand[runtime] else { return Color.secondary.opacity(0.15) }
        return Color(hex: hex).opacity(0.45)
    }

    private static let brand: [String: UInt32] = [
        "Docker": 0x2496ED, "Node": 0x5FA04E, "Nuxt": 0x00DC82, "Vite": 0x646CFF,
        "Astro": 0xFF5D01, "Webpack": 0x2D7CB8, "Python": 0x4B8BBE, "Django": 0x44B78B,
        "Rails": 0xCC0000, "uvicorn": 0x2094F3, "gunicorn": 0x499848, "Postgres": 0x6699CC,
        "Redis": 0xFF4438, "MySQL": 0xF29111, "Mongo": 0x47A248, "Elasticsearch": 0xFEC514,
        "Go": 0x00ADD8, "Bun": 0xE3B261,
    ]
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text("Nothing listening on localhost")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

// MARK: - Settings (inline panel, reactive via @EnvironmentObject prefs)

struct SettingsPanel: View {
    @EnvironmentObject var prefs: Preferences

    /// CFBundleVersion carries the full `git describe` output; the short string
    /// is only the numeric part Apple allows.
    private static var version: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Show system processes", isOn: $prefs.showSystem)
            Toggle("Show background apps", isOn: $prefs.showBackgroundApps)
            Toggle("Launch at login", isOn: $prefs.launchAtLogin)
            Toggle("Notify when a pinned port stops", isOn: $prefs.notifyOnStopPinned)

            // the build this came from, so "am I on the latest?" is answerable
            Text(verbatim: "Portside \(Self.version)")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .font(.system(size: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }
}

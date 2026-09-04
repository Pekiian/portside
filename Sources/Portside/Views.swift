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

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if showSettings {
                SettingsPanel()
            } else if model.rows.isEmpty {
                EmptyStateView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.rows) { row in
                            ListenerRow(
                                row: row,
                                isEditing: editingPort == row.port,
                                draft: $draft,
                                onBeginRename: { beginRename(row) },
                                onCommit: commitRename,
                                onCancel: { editingPort = nil }
                            )
                            if row.id != model.rows.last?.id { Divider().opacity(0.4) }
                        }
                    }
                }
                // ScrollView has no intrinsic height in a content-sized window;
                // size it to the rows, capped so the whole popover stays ~500pt.
                .frame(height: min(CGFloat(model.rows.count) * 46, 400))
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
    @EnvironmentObject var model: AppModel
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
                .font(.system(size: 11))
                .foregroundStyle(.orange)
        } else if let l = row.listener {
            // container image, workspace path, or the process name when
            // nothing else has named the row. Full detail on hover.
            Text(verbatim: l.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.head)
                .help("\(l.cwd ?? "")\n\(l.processName) · \(l.pid)")
        } else {
            Text("not listening")
                .font(.system(size: 11))
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
            if row.listener?.cwd != nil {
                Button("Open cwd in Terminal") { model.openTerminal(row) }
                Button("Reveal cwd in Finder") { model.revealInFinder(row) }
            }
        }
        Button(model.prefs.isPinned(row.port) ? "Unpin" : "Pin") {
            model.prefs.togglePin(row.port)
        }
        Button("Rename", action: onBeginRename)
        if row.isListening {
            Divider()
            Button("Kill") { model.kill(row, force: false) }
            Button("Force Kill", role: .destructive) { model.kill(row, force: true) }
        }
    }
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
            .background(Color.secondary.opacity(0.15), in: Capsule())
            .foregroundStyle(.secondary)
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
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Show system processes", isOn: $prefs.showSystem)
            Toggle("Launch at login", isOn: $prefs.launchAtLogin)
            Toggle("Notify when a pinned port stops", isOn: $prefs.notifyOnStopPinned)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .font(.system(size: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }
}

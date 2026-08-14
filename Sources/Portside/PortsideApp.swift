import SwiftUI

@main
struct PortsideApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(model)
                .environmentObject(model.prefs)
                .onAppear { model.isMenuOpen = true; model.requestNotificationAuthIfNeeded() }
                .onDisappear { model.isMenuOpen = false }
        } label: {
            MenuBarLabel(count: model.badgeCount)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Menu bar icon + a compact count badge. No text label hogging the bar.
struct MenuBarLabel: View {
    let count: Int
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "network")
            if count > 0 {
                Text(verbatim: String(count))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
            }
        }
    }
}

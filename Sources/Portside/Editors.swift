import AppKit

/// An installed editor that can open a directory.
struct Editor: Identifiable {
    let name: String
    let url: URL
    var id: String { url.path }
}

enum Editors {
    /// Looked up by bundle id rather than by path, so an editor installed in
    /// `~/Applications` or renamed on disk is still found.
    private static let known: [(name: String, bundleID: String)] = [
        ("VS Code", "com.microsoft.VSCode"),
        ("VS Code Insiders", "com.microsoft.VSCodeInsiders"),
        ("VSCodium", "com.vscodium"),
        ("Cursor", "com.todesktop.230313mzl4w4u92"),
        ("Windsurf", "com.exafunction.windsurf"),
        ("Zed", "dev.zed.Zed"),
        ("Sublime Text", "com.sublimetext.4"),
        ("Nova", "com.panic.Nova"),
        ("BBEdit", "com.barebones.bbedit"),
        ("WebStorm", "com.jetbrains.WebStorm"),
        ("IntelliJ IDEA", "com.jetbrains.intellij"),
        ("PyCharm", "com.jetbrains.pycharm"),
        ("GoLand", "com.jetbrains.goland"),
        ("RubyMine", "com.jetbrains.rubymine"),
        ("Xcode", "com.apple.dt.Xcode"),
    ]

    /// Resolved once. Scanning LaunchServices on every right-click is wasteful,
    /// and installing an editor while a menu bar app runs is rare enough to
    /// cost a relaunch.
    static let installed: [Editor] = known.compactMap { entry in
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleID)
        else { return nil }
        return Editor(name: entry.name, url: url)
    }

    static func open(_ path: String, in editor: Editor) {
        NSWorkspace.shared.open([URL(fileURLWithPath: path)],
                                withApplicationAt: editor.url,
                                configuration: NSWorkspace.OpenConfiguration())
    }
}

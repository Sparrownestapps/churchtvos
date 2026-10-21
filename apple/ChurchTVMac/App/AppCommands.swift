import SwiftUI
import AppKit

/// The menu bar of the app (File, View, Go, Window, Help). The App, Edit and Window menus keep their standard items.
struct AppCommands: Commands {
    let model: MenuModel
    @Environment(\.openWindow) private var openWindow
    private var web: WebModel { model.web }

    var body: some Commands {
        // File
        CommandGroup(replacing: .newItem) {
            Button("Open Dashboard in Browser") { NSWorkspace.shared.open(AppLinks.dashboard) }
                .keyboardShortcut("o", modifiers: [.command, .shift])
        }

        // View
        CommandGroup(before: .toolbar) {
            Button("Reload") { web.reload() }.keyboardShortcut("r")
            Button("Back") { web.goBack() }.keyboardShortcut("[").disabled(!web.canGoBack)
            Button("Forward") { web.goForward() }.keyboardShortcut("]").disabled(!web.canGoForward)
            Divider()
            Button("Actual Size") { web.resetZoom() }.keyboardShortcut("0")
            Button("Zoom In") { web.zoomIn() }.keyboardShortcut("+")
            Button("Zoom Out") { web.zoomOut() }.keyboardShortcut("-")
            Divider()
        }

        // Go: the website's main sections
        CommandMenu("Go") {
            ForEach(Array(AppLinks.Section.allCases.enumerated()), id: \.element) { i, section in
                Button(section.title) { show(); web.open(section) }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
            }
        }

        // Window
        CommandGroup(after: .windowArrangement) {
            Button("Show Church TV OS Window") { show() }.keyboardShortcut("0", modifiers: [.command, .option])
            Button("Show TV Status") { openWindow(id: "status"); NSApp.activate(ignoringOtherApps: true) }
                .keyboardShortcut("t", modifiers: [.command, .shift])
        }

        // Help
        CommandGroup(replacing: .help) {
            Button("Church TV OS Help") { NSWorkspace.shared.open(AppLinks.help) }.keyboardShortcut("?")
            Divider()
            Button("Privacy Policy") { NSWorkspace.shared.open(AppLinks.privacy) }
            Button("Terms of Service") { NSWorkspace.shared.open(AppLinks.terms) }
            Button("Delete My Account") { NSWorkspace.shared.open(AppLinks.deleteAccount) }
        }
    }

    private func show() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

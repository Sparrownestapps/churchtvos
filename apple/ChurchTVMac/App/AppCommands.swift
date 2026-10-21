import SwiftUI
import AppKit
import ChurchTVCore

/// The menu bar of the app: File, View (sidebar), Go (sections), Remote, Window, Help. App, Edit and Window keep their standard items.
struct AppCommands: Commands {
    let model: MenuModel
    @Environment(\.openWindow) private var openWindow
    private var nav: NavState { NavState.shared }

    private var visible: [AppSection] { AppSection.visible(church: model.church, isPlatformAdmin: model.isPlatformAdmin) }
    private var control: Bool { model.isSignedIn && model.canControl && (model.selectedScreen?.isOnline() ?? false) && (model.selectedScreen?.supportsRemote ?? false) }

    var body: some Commands {
        SidebarCommands()

        // File
        CommandGroup(replacing: .newItem) {
            Button("Pair a TV…") { show(); nav.go(.screens); nav.showPairSheet = true }
                .keyboardShortcut("n", modifiers: [.command, .option]).disabled(!(model.church.map { ScreenRules.canManage($0.role) } ?? false))
            Divider()
            Button("Refresh") { Task { await model.refreshNow() } }.keyboardShortcut("r").disabled(!model.isSignedIn)
            Button("Open Dashboard in Browser") { NSWorkspace.shared.open(AppLinks.dashboard) }.keyboardShortcut("o", modifiers: [.command, .shift])
        }

        // Go: sections the signed-in person can see
        CommandMenu("Go") {
            ForEach(Array(visible.prefix(10).enumerated()), id: \.element) { i, section in
                Button(section.title) { show(); nav.go(section) }
                    .keyboardShortcut(KeyEquivalent(Character("\((i + 1) % 10)")))
            }
            if visible.isEmpty { Text("Sign in to see sections") }
        }

        // Remote (acts on the TV selected in Screens / Remote / the menu bar)
        CommandMenu("Remote") {
            Button("Next Slide") { send(.next) }.keyboardShortcut(.rightArrow, modifiers: [.command, .option]).disabled(!control)
            Button("Previous Slide") { send(.previous) }.keyboardShortcut(.leftArrow, modifiers: [.command, .option]).disabled(!control)
            Button("Blank / Unblank") { send(.blank(on: nil)) }.keyboardShortcut("b", modifiers: [.command, .option]).disabled(!control)
            Button("Stop") { send(.stop) }.keyboardShortcut(".", modifiers: [.command, .option]).disabled(!control)
            Divider()
            Button("Send Message…") { show(); nav.go(.remote); nav.showMessageSheet = true }
                .keyboardShortcut("m", modifiers: [.command, .option]).disabled(!control)
            Button("Open Remote") { show(); nav.go(.remote) }.disabled(!model.isSignedIn)
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

    private func send(_ c: RemoteCommand) {
        guard let s = model.selectedScreen else { return }
        Task { await model.send(c, to: s) }
    }

    private func show() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

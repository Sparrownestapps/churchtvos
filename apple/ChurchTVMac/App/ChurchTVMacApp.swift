import SwiftUI
import AppKit
import ChurchTVCore
import ChurchTVEditors

@main
struct ChurchTVMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("showMenuBarItem") private var showMenuBar = true
    private let model = MenuModel.shared

    var body: some Scene {
        Window("Church TV OS", id: "main") {
            NativeRootView()
                .environment(model)
                .environment(model.content)
        }
        .defaultSize(width: 1280, height: 820)
        .commands { AppCommands(model: model) }

        Window("TV Status", id: "status") {
            MenuBarView().environment(model)
        }
        .windowResizability(.contentSize)

        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarView().environment(model)
        } label: {
            Image(nsImage: MenuBarIcon.image(for: model.status))
                .accessibilityLabel("Church TV OS: \(model.status.summary)")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environment(model)
        }
    }
}

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Dock icon preference (default on). Menu-bar-only mode hides the Dock icon.
        if UserDefaults.standard.object(forKey: "showDockIcon") as? Bool == false { NSApp.setActivationPolicy(.accessory) }
    }

    @MainActor func applicationDidFinishLaunching(_ notification: Notification) {
        PushManager.shared.start()
        MenuModel.shared.start()
    }

    /// Closing the window leaves the menu bar item running; with no menu bar item the app quits with its last window.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        UserDefaults.standard.object(forKey: "showMenuBarItem") as? Bool == false
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in PushManager.shared.didRegister(token: token) }
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in PushManager.shared.didFail(error: error) }
    }
}

import SwiftUI
import UIKit
import ChurchTVCore
import ChurchTVEditors

@main
struct ChurchTVRemoteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.content)   // the shared editors (ChurchTVEditors) read their state from ContentModel
                .task { await model.bootstrap() }
        }
    }
}

/// Receives the APNs callbacks, which SwiftUI does not expose.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in PushManager.shared.didRegister(token: token) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in PushManager.shared.didFail(error: error) }
    }
}

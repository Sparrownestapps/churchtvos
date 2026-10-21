import AppKit
import UserNotifications
import Observation
import ChurchTVCore

/// Client side of offline-alert push notifications on the Mac (same `push_devices` contract as the iPhone app, platform 'macos').
/// The permission prompt only appears when someone turns alerts on in Settings.
@MainActor
@Observable
final class PushManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PushManager()

    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var token: String? = UserDefaults.standard.string(forKey: "apnsToken")
    private(set) var lastError: String?
    @ObservationIgnored var onToken: ((String) -> Void)?

    /// Debug builds use the APNs sandbox, release builds production.
    static var environment: PushEnvironment {
        #if DEBUG
        .sandbox
        #else
        .production
        #endif
    }

    var isAuthorized: Bool { authorization == .authorized || authorization == .provisional }
    var isDenied: Bool { authorization == .denied }

    func start() {
        UNUserNotificationCenter.current().delegate = self
        Task { await refreshAuthorization() }
    }

    func refreshAuthorization() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    @discardableResult
    func enable() async -> Bool {
        lastError = nil
        do { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) }
        catch { lastError = error.localizedDescription }
        await refreshAuthorization()
        if isAuthorized { NSApplication.shared.registerForRemoteNotifications() }
        return isAuthorized
    }

    func refreshRegistrationIfAllowed() async {
        await refreshAuthorization()
        if isAuthorized { NSApplication.shared.registerForRemoteNotifications() }
    }

    func didRegister(token: String) {
        self.token = token
        UserDefaults.standard.set(token, forKey: "apnsToken")
        onToken?(token)
    }

    func didFail(error: Error) {
        lastError = "Could not register for notifications: \(error.localizedDescription)"
    }

    func forgetToken() {
        token = nil
        UserDefaults.standard.removeObject(forKey: "apnsToken")
    }

    // Show banners while the app is in front too.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

import Foundation
import UIKit
import UserNotifications
import Observation
import ChurchTVCore

/// Client side of offline-alert push notifications. The permission prompt is only ever triggered from Settings.
/// The token goes to the `push_devices` table (see README for the contract); the server side is built separately.
@MainActor
@Observable
final class PushManager {
    static let shared = PushManager()

    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var token: String? = UserDefaults.standard.string(forKey: "apnsToken")
    private(set) var lastError: String?

    /// Set by AppModel: called with each new or refreshed token so it can be stored for the signed-in user.
    @ObservationIgnored var onToken: ((String) -> Void)?

    /// Debug builds talk to the APNs sandbox, release (TestFlight / App Store) builds to production.
    static var environment: PushEnvironment {
        #if DEBUG
        .sandbox
        #else
        .production
        #endif
    }

    var isAuthorized: Bool { authorization == .authorized || authorization == .provisional || authorization == .ephemeral }
    var isDenied: Bool { authorization == .denied }

    func refreshAuthorization() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Asks permission (first time only) and registers for remote notifications. Returns true when allowed.
    @discardableResult
    func enable() async -> Bool {
        lastError = nil
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            lastError = error.localizedDescription
        }
        await refreshAuthorization()
        if isAuthorized { UIApplication.shared.registerForRemoteNotifications() }
        return isAuthorized
    }

    /// Called on every launch once signed in: tokens can change, so ask again silently if already allowed.
    func refreshRegistrationIfAllowed() async {
        await refreshAuthorization()
        if isAuthorized { UIApplication.shared.registerForRemoteNotifications() }
    }

    func didRegister(token: String) {
        self.token = token
        UserDefaults.standard.set(token, forKey: "apnsToken")
        onToken?(token)
    }

    func didFail(error: Error) {
        // Expected on simulators without push support; the toggle still saves the preference.
        lastError = "Could not register for notifications: \(error.localizedDescription)"
    }

    func forgetToken() {
        token = nil
        UserDefaults.standard.removeObject(forKey: "apnsToken")
    }
}

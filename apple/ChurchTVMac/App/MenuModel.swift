import Foundation
import Observation
import SwiftUI
import ChurchTVCore

/// App-wide state for the menu bar item and Settings: session (shared with the website through the bridge), church, screens, commands.
@MainActor
@Observable
final class MenuModel {
    static let shared = MenuModel()

    enum Source: String { case none, web, native }

    let web = WebModel()
    @ObservationIgnored private let supabase = SupabaseService(pushPlatform: "macos", autoRefreshToken: false)
    private(set) var service: any ChurchService

    private(set) var user: SessionUser?
    private(set) var churches: [ChurchAccess] = []
    private(set) var church: ChurchAccess?
    private(set) var screens: [ScreenInfo] = []
    private(set) var lastRefresh: Date?
    private(set) var loadError: String?
    private(set) var bridgeNote: String?
    var commandError: String?
    var selectedScreenId: UUID?
    var signInError: String?
    var isSigningIn = false

    /// True while the menu bar popover (or the status window) is on screen: refresh every 3 s instead of 15 s.
    var popoverOpen: Bool { openViews > 0 }
    private var openViews = 0
    /// Called by each visible copy of the popover content (menu bar popover, status window).
    func viewAppeared() { openViews += 1; if openViews == 1 { Task { await refreshNow() } } }
    func viewDisappeared() { openViews = max(0, openViews - 1) }

    private(set) var useDemo: Bool
    @ObservationIgnored private var source: Source
    @ObservationIgnored private var adoptedAccessToken: String?
    @ObservationIgnored private var failedAccessToken: String?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var busy = false
    let push = PushManager.shared

    private enum Keys {
        static let demo = "useDemoData", source = "sessionSource", church = "lastChurchId"
    }

    private init() {
        let d = UserDefaults.standard
        let demo = d.bool(forKey: Keys.demo) || CommandLine.arguments.contains("-demo")
        useDemo = demo
        source = Source(rawValue: d.string(forKey: Keys.source) ?? "") ?? .none
        service = demo ? MockService() : supabase
        push.onToken = { [weak self] token in Task { @MainActor in await self?.storePushToken(token) } }
    }

    // MARK: Derived

    var isSignedIn: Bool { user != nil }
    var status: MenuBarStatus { MenuBarStatus.rollup(signedIn: isSignedIn, screens: screens) }
    var selectedScreen: ScreenInfo? { screens.first { $0.id == selectedScreenId } ?? screens.first }
    var canControl: Bool { church?.role.canControl ?? false }
    var roleText: String { church?.role.displayName ?? "" }

    // MARK: Lifecycle

    func start() {
        guard loop == nil else { return }
        web.loadHome()
        loop = Task { [weak self] in
            // Fast path: a session the SDK kept in the Keychain from last time.
            await self?.restoreAtLaunch()
            while !Task.isCancelled {
                await self?.tick()
                var waited = 0
                while !Task.isCancelled, let s = self, waited < (s.popoverOpen ? 3 : 15) {
                    try? await Task.sleep(for: .seconds(1)); waited += 1
                }
            }
        }
    }

    private func restoreAtLaunch() async {
        if useDemo { await enterDemo(); return }
        if let u = await supabase.restoreSession() {
            user = u
            await loadChurches()
        }
    }

    func refreshNow() async { await tick() }

    private func tick() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        if useDemo {
            if user == nil { await enterDemo() }
            await refreshScreens(); return
        }
        await syncSession()
        if user != nil {
            if church == nil && churches.isEmpty { await loadChurches() }
            await refreshScreens()
        }
    }

    // MARK: Session bridge

    /// Compares the website's session with ours. The website owns the refresh token; we only ever adopt tokens that are still valid
    /// (so the SDK never refreshes and never rotates the website's refresh token).
    private func syncSession() async {
        switch await web.readSession() {
        case .session(let s):
            if s.isFresh() {
                bridgeNote = nil
                if user == nil || s.accessToken != adoptedAccessToken { await adopt(s) }
            } else if user == nil {
                bridgeNote = "The website sign-in needs a refresh. Open the dashboard window and this will connect automatically."
            }
        case .signedOut:
            bridgeNote = nil
            if source == .web, user != nil {
                // Signed out on the website: clear ours too.
                await clearLocalSession(removeWebSession: false)
            }
        case .unavailable:
            break
        }
    }

    private func adopt(_ s: WebSession) async {
        guard s.accessToken != failedAccessToken else { return }
        do {
            let u = try await supabase.setSession(accessToken: s.accessToken, refreshToken: s.refreshToken)
            adoptedAccessToken = s.accessToken
            failedAccessToken = nil
            let firstTime = user == nil
            user = u
            setSource(.web)
            if firstTime || churches.isEmpty { await loadChurches() }
        } catch {
            failedAccessToken = s.accessToken
            bridgeNote = "Could not connect the menu bar to your website sign-in: \(Formatting.message(for: error))"
        }
    }

    private func setSource(_ s: Source) {
        source = s
        UserDefaults.standard.set(s.rawValue, forKey: Keys.source)
    }

    // MARK: Sign in / out

    /// Fallback: sign in natively (Settings) when the bridge is not wanted. The menu bar then works without the website session.
    func signIn(email: String, password: String) async {
        signInError = nil
        guard !email.trimmingCharacters(in: .whitespaces).isEmpty, !password.isEmpty else { signInError = "Enter your email and password."; return }
        isSigningIn = true; defer { isSigningIn = false }
        do {
            useDemoFlag(false)
            service = supabase
            user = try await supabase.signIn(email: email, password: password)
            setSource(.native)
            await loadChurches()
        } catch {
            signInError = Formatting.message(for: error)
        }
    }

    /// Signs out of the menu bar and the website.
    func signOut() async {
        if useDemo { await setDemo(false); return }
        await clearLocalSession(removeWebSession: true)
    }

    private func clearLocalSession(removeWebSession: Bool) async {
        if let token = push.token { try? await service.removePushToken(token) }   // needs the session: do it first
        push.forgetToken()
        await supabase.signOut()
        adoptedAccessToken = nil; failedAccessToken = nil
        setSource(.none)
        resetData()
        if removeWebSession { await web.clearSessionAndReload() }
    }

    private func resetData() {
        user = nil; churches = []; church = nil; screens = []; selectedScreenId = nil; lastRefresh = nil; loadError = nil
    }

    private func useDemoFlag(_ on: Bool) {
        useDemo = on
        UserDefaults.standard.set(on, forKey: Keys.demo)
    }

    // MARK: Demo

    func setDemo(_ on: Bool) async {
        guard on != useDemo else { return }
        useDemoFlag(on)
        resetData()
        if on {
            await enterDemo()
        } else {
            service = supabase
            await restoreAtLaunch()
            await tick()
        }
    }

    private func enterDemo() async {
        service = MockService()
        user = MockService.demoUser
        await loadChurches()
        await refreshScreens()
    }

    // MARK: Churches and screens

    private func loadChurches() async {
        do {
            churches = try await service.loadChurches()
            loadError = nil
        } catch {
            loadError = Formatting.message(for: error); churches = []
        }
        guard !churches.isEmpty else { church = nil; return }
        if let current = church, let again = churches.first(where: { $0.id == current.id }) { church = again; return }
        let last = UserDefaults.standard.string(forKey: Keys.church).flatMap(UUID.init(uuidString:))
        await choose(churches.first(where: { $0.id == last }) ?? churches[0])
    }

    func choose(_ access: ChurchAccess) async {
        church = access
        if !useDemo { UserDefaults.standard.set(access.id.uuidString, forKey: Keys.church) }
        screens = []; selectedScreenId = nil
        await refreshScreens()
        if !useDemo { await push.refreshRegistrationIfAllowed() }
    }

    func refreshScreens() async {
        guard let church else { return }
        do {
            let list = try await service.listScreens(organizationId: church.id)
            screens = list
            lastRefresh = Date()
            loadError = nil
            if selectedScreenId == nil || !list.contains(where: { $0.id == selectedScreenId }) { selectedScreenId = list.first?.id }
        } catch {
            if !(error is CancellationError) { loadError = Formatting.message(for: error) }
        }
    }

    // MARK: Commands

    @discardableResult
    func send(_ command: RemoteCommand, to screen: ScreenInfo) async -> Bool {
        commandError = nil
        do {
            try await service.send(command, to: screen.id)
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(500)); await self?.refreshScreens()
                try? await Task.sleep(for: .milliseconds(1200)); await self?.refreshScreens()
            }
            return true
        } catch {
            commandError = Formatting.message(for: error)
            return false
        }
    }

    // MARK: Notifications

    func offlineAlertsEnabled() async -> Bool {
        guard let church, !useDemo else { return false }
        return (try? await service.offlineAlertsEnabled(organizationId: church.id)) ?? false
    }

    /// Returns an error text, or nil on success. Turning on asks for permission (first time) and registers the token.
    func setOfflineAlerts(_ enabled: Bool) async -> String? {
        guard let church, !useDemo else { return nil }
        do {
            if enabled {
                let allowed = await push.enable()
                if !allowed { return push.isDenied ? "Notifications are turned off for Church TV OS in System Settings." : push.lastError }
                if let token = push.token { await storePushToken(token) }
            }
            try await service.setOfflineAlerts(organizationId: church.id, enabled: enabled)
            return nil
        } catch {
            return Formatting.message(for: error)
        }
    }

    private func storePushToken(_ token: String) async {
        guard user != nil, !useDemo else { return }
        try? await service.registerPushToken(token, environment: PushManager.environment)
    }
}

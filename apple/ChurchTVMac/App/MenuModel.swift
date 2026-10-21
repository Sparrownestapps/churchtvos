import Foundation
import Observation
import SwiftUI
import ChurchTVCore
import ChurchTVEditors

/// App-wide state for the native app, the menu bar item and Preferences: the native session (Supabase, tokens in the Keychain), churches,
/// screens, remote commands, and the editors' host (`ContentHost`). The website web view is only a fallback and has its own sign-in.
@MainActor
@Observable
final class MenuModel {
    static let shared = MenuModel()

    let web = WebModel()
    /// The app owns its session, so the SDK refreshes the token itself (the website in the fallback pane keeps a separate session).
    @ObservationIgnored private let supabase = SupabaseService(pushPlatform: "macos", autoRefreshToken: true)
    private(set) var service: any ChurchService

    private(set) var user: SessionUser?
    private(set) var churches: [ChurchAccess] = []
    private(set) var church: ChurchAccess?
    private(set) var screens: [ScreenInfo] = []
    private(set) var lastRefresh: Date?
    private(set) var loadError: String?
    /// True until the saved session (Keychain) has been checked at launch, so the window does not flash the sign-in screen.
    private(set) var launching = true
    private(set) var isPlatformAdmin = false
    /// Released applications (the `modules` registry), for People and names.
    private(set) var moduleRegistry: [ModuleDef] = []
    /// Bumped after screens were edited, paired or unpaired, so views reload their own details.
    private(set) var screensRevision = 0
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
    /// The editors' state (Create section, pickers, media). Created on first use.
    @ObservationIgnored private(set) lazy var content = ContentModel(host: self)
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var busy = false
    let push = PushManager.shared

    private enum Keys {
        static let demo = "useDemoData", church = "lastChurchId"
    }

    private init() {
        let d = UserDefaults.standard
        let demo = d.bool(forKey: Keys.demo) || CommandLine.arguments.contains("-demo")
        useDemo = demo
        service = demo ? MockService() : supabase
        push.onToken = { [weak self] token in Task { @MainActor in await self?.storePushToken(token) } }
    }

    // MARK: Derived

    var isSignedIn: Bool { user != nil }
    var status: MenuBarStatus { MenuBarStatus.rollup(signedIn: isSignedIn, screens: screens) }
    var selectedScreen: ScreenInfo? { screens.first { $0.id == selectedScreenId } ?? screens.first }
    var canControl: Bool { church?.role.canControl ?? false }
    var roleText: String { church?.role.displayName ?? "" }
    var ops: (any OperationsService)? { service as? any OperationsService }
    var library: (any LibraryService)? { service as? any LibraryService }
    var admin: (any AdminService)? { service as? any AdminService }
    var offlineCount: Int { screens.filter { !$0.isOnline() }.count }
    func moduleName(_ id: String) -> String { moduleRegistry.first { $0.id == id }?.name ?? AppModule(rawValue: id)?.displayName ?? id.capitalized }

    // MARK: Lifecycle

    func start() {
        guard loop == nil else { return }
        web.loadHome()
        loop = Task { [weak self] in
            // Fast path: a session the SDK kept in the Keychain from last time.
            await self?.restoreAtLaunch()
            self?.launching = false
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
        if user != nil {
            if church == nil && churches.isEmpty { await loadChurches() }
            await refreshScreens()
        }
    }

    // MARK: Sign in / out

    /// Native sign-in with the same account as the website. The SDK keeps the session in the Keychain and refreshes it.
    func signIn(email: String, password: String) async {
        signInError = nil
        guard !email.trimmingCharacters(in: .whitespaces).isEmpty, !password.isEmpty else { signInError = "Enter your email and password."; return }
        isSigningIn = true; defer { isSigningIn = false }
        do {
            useDemoFlag(false)
            service = supabase
            user = try await supabase.signIn(email: email, password: password)
            await loadChurches()
        } catch {
            signInError = Formatting.message(for: error)
        }
    }

    /// Signs out of the app (and clears the fallback web view's sign-in).
    func signOut() async {
        if useDemo { await setDemo(false); return }
        await clearLocalSession(removeWebSession: true)
    }

    private func clearLocalSession(removeWebSession: Bool) async {
        if let token = push.token { try? await service.removePushToken(token) }   // needs the session: do it first
        push.forgetToken()
        await supabase.signOut()
        resetData()
        if removeWebSession { await web.clearSessionAndReload() }
    }

    private func resetData() {
        user = nil; churches = []; church = nil; screens = []; selectedScreenId = nil; lastRefresh = nil; loadError = nil
        isPlatformAdmin = false; moduleRegistry = []
        content.reset()
        updateDockBadge()
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
        isPlatformAdmin = (try? await ops?.isPlatformAdmin()) ?? false
        moduleRegistry = (try? await ops?.listModules(availableOnly: true)) ?? []
        guard !churches.isEmpty else { church = nil; return }
        if let current = church, let again = churches.first(where: { $0.id == current.id }) { church = again; return }
        let last = UserDefaults.standard.string(forKey: Keys.church).flatMap(UUID.init(uuidString:))
        await choose(churches.first(where: { $0.id == last }) ?? churches[0])
    }

    /// Re-reads the churches (after the name or branding changed).
    func reloadChurches() async { await loadChurches() }

    func choose(_ access: ChurchAccess) async {
        church = access
        if !useDemo { UserDefaults.standard.set(access.id.uuidString, forKey: Keys.church) }
        content.reset()
        screens = []; selectedScreenId = nil
        await refreshScreens()
        if !useDemo { await push.refreshRegistrationIfAllowed() }
    }

    func refreshScreens() async {
        guard let church else { return }
        do {
            var list = try await service.listScreens(organizationId: church.id)
            if let ops { list = await ops.overlayScreens(list) }
            screens = list
            updateDockBadge()
            lastRefresh = Date()
            loadError = nil
            if selectedScreenId == nil || !list.contains(where: { $0.id == selectedScreenId }) { selectedScreenId = list.first?.id }
        } catch {
            if !(error is CancellationError) { loadError = Formatting.message(for: error) }
        }
    }

    /// Edits, pairing and unpairing change the list: read it again right away.
    func screensChanged() async { screensRevision += 1; await refreshScreens() }

    /// Dock badge = number of TVs that are offline (none = no badge).
    private func updateDockBadge() {
        let n = isSignedIn ? offlineCount : 0
        NSApp?.dockTile.badgeLabel = n > 0 ? "\(n)" : nil
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

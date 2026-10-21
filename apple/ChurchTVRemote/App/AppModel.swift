import Foundation
import Observation
import SwiftUI
import ChurchTVCore

/// App-wide state: session, current church, screens and their live status.
@MainActor
@Observable
final class AppModel {
    enum Phase { case launching, signedOut, chooseChurch, ready }

    // Session
    private(set) var phase: Phase = .launching
    private(set) var service: any ChurchService
    private(set) var user: SessionUser?
    private(set) var churches: [ChurchAccess] = []
    private(set) var church: ChurchAccess?
    var isDemo: Bool { service.isDemo }

    // Data
    private(set) var screens: [ScreenInfo] = []
    private(set) var lastRefresh: Date?
    private(set) var loadError: String?
    private(set) var isLoading = false
    private(set) var playNowItems: [PlayNowItem] = []
    private(set) var schedule: [ScheduleEntry] = []
    private(set) var scheduleLoaded = false

    // UI state
    var selectedScreenId: UUID?
    var signInError: String?
    var isSigningIn = false
    /// Last error from a remote command (shown in the Remote screen).
    var commandError: String?
    var iPhoneTab: AppTab = .screens

    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private let lastChurchKey = "lastChurchId"

    let push = PushManager.shared

    init(service: any ChurchService = SupabaseService()) {
        self.service = service
        push.onToken = { [weak self] token in
            Task { @MainActor in await self?.storePushToken(token) }
        }
    }

    // MARK: Derived

    var selectedScreen: ScreenInfo? { screens.first { $0.id == selectedScreenId } }
    var canControl: Bool { church?.role.canControl ?? false }
    var canAddMedia: Bool { (church?.role.canEditContent ?? false) && !(church?.modules.isEmpty ?? true) }

    // MARK: Launch and sign-in

    func bootstrap() async {
        guard phase == .launching else { return }
        // Launch arguments used for automated screenshots and UI checks: -demo, -tab <screens|remote|today|settings>.
        let args = CommandLine.arguments
        if args.contains("-demo") {
            await startDemo()
            if let i = args.firstIndex(of: "-tab"), i + 1 < args.count {
                switch args[i + 1] {
                case "remote": iPhoneTab = .remote
                case "today": iPhoneTab = .today
                case "settings": iPhoneTab = .settings
                default: break
                }
            }
            return
        }
        if let u = await service.restoreSession() {
            user = u
            await loadChurches(autoSelect: true)
        } else {
            phase = .signedOut
        }
    }

    func signIn(email: String, password: String) async {
        signInError = nil
        guard !email.trimmingCharacters(in: .whitespaces).isEmpty, !password.isEmpty else {
            signInError = "Enter your email and password."
            return
        }
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            user = try await service.signIn(email: email, password: password)
            await loadChurches(autoSelect: true)
        } catch {
            signInError = Formatting.message(for: error)
            Haptics.failure()
        }
    }

    func startDemo() async {
        service = MockService()
        user = MockService.demoUser
        signInError = nil
        await loadChurches(autoSelect: true)
    }

    func signOut() async {
        stopAutoRefresh()
        if !service.isDemo, let token = push.token { try? await service.removePushToken(token) }
        push.forgetToken()
        await service.signOut()
        if service.isDemo { service = SupabaseService() }
        user = nil; churches = []; church = nil; screens = []; schedule = []; playNowItems = []
        selectedScreenId = nil; lastRefresh = nil; loadError = nil; scheduleLoaded = false
        iPhoneTab = .screens
        phase = .signedOut
    }

    // MARK: Churches

    func loadChurches(autoSelect: Bool) async {
        do {
            churches = try await service.loadChurches()
        } catch {
            // Keep the session; show the picker/empty state with the error.
            loadError = Formatting.message(for: error)
            churches = []
        }
        if churches.isEmpty { phase = .chooseChurch; return }
        if autoSelect {
            let last = UserDefaults.standard.string(forKey: lastChurchKey).flatMap(UUID.init(uuidString:))
            if churches.count == 1 { await choose(churches[0]) }
            else if let last, let c = churches.first(where: { $0.id == last }) { await choose(c) }
            else { phase = .chooseChurch }
        } else {
            phase = .chooseChurch
        }
    }

    func choose(_ access: ChurchAccess) async {
        church = access
        if !isDemo { UserDefaults.standard.set(access.id.uuidString, forKey: lastChurchKey) }
        screens = []; schedule = []; playNowItems = []; selectedScreenId = nil; scheduleLoaded = false; loadError = nil
        phase = .ready
        await refreshScreens()
        selectedScreenId = screens.first(where: { $0.isOnline() && $0.supportsRemote })?.id ?? screens.first?.id
        await loadPlayNow()
        if !isDemo { await push.refreshRegistrationIfAllowed() }
    }

    func switchChurch() {
        stopAutoRefresh()
        phase = .chooseChurch
    }

    // MARK: Screens and live refresh

    func refreshScreens() async {
        guard let church else { return }
        isLoading = screens.isEmpty
        defer { isLoading = false }
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

    /// Refreshes every 3 seconds until stopped (called while the app is active and signed in).
    func startAutoRefresh() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if Task.isCancelled { break }
                await self?.refreshScreens()
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: Commands

    /// Sends a command with haptics. Server messages (for example the rate limit) go to `commandError`.
    @discardableResult
    func send(_ command: RemoteCommand, to screen: ScreenInfo) async -> Bool {
        commandError = nil
        do {
            try await service.send(command, to: screen.id)
            Haptics.success()
            // Pull the new status quickly instead of waiting for the next 3-second tick.
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 500_000_000); await self?.refreshScreens()
                try? await Task.sleep(nanoseconds: 1_200_000_000); await self?.refreshScreens()
            }
            return true
        } catch {
            commandError = Formatting.message(for: error)
            Haptics.failure()
            return false
        }
    }

    func loadPlayNow() async {
        guard let church else { return }
        playNowItems = (try? await service.playNowItems(organizationId: church.id, modules: church.modules)) ?? []
    }

    func loadSchedule() async {
        guard let church else { return }
        do {
            schedule = try await service.schedule(organizationId: church.id, screens: screens, modules: church.modules, now: Date())
            scheduleLoaded = true
        } catch {
            loadError = Formatting.message(for: error)
        }
    }

    // MARK: Media

    func folders(for module: AppModule) async -> [MediaFolder] {
        guard let church else { return [] }
        return (try? await service.mediaFolders(organizationId: church.id, module: module)) ?? []
    }

    func upload(_ request: MediaUploadRequest, progress: @escaping @Sendable (Double) -> Void) async throws {
        try await service.uploadMedia(request, progress: progress)
    }

    // MARK: Notifications

    func offlineAlertsEnabled() async -> Bool {
        guard let church else { return false }
        return (try? await service.offlineAlertsEnabled(organizationId: church.id)) ?? false
    }

    /// Turns offline alerts on or off for the current church. Turning on asks for permission (first time) and registers the token.
    func setOfflineAlerts(_ enabled: Bool) async -> String? {
        guard let church else { return nil }
        do {
            if enabled && !isDemo {
                let allowed = await push.enable()
                if !allowed { return push.isDenied ? "Notifications are turned off for this app in iOS Settings." : push.lastError }
                if let token = push.token { await storePushToken(token) }
            }
            try await service.setOfflineAlerts(organizationId: church.id, enabled: enabled)
            return nil
        } catch {
            return Formatting.message(for: error)
        }
    }

    private func storePushToken(_ token: String) async {
        guard user != nil, !isDemo else { return }
        try? await service.registerPushToken(token, environment: PushManager.environment)
    }
}

enum AppTab: Hashable { case screens, remote, today, settings }

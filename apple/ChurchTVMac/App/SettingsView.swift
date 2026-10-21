import SwiftUI
import ServiceManagement
import AppKit
import ChurchTVCore

struct SettingsView: View {
    @Environment(MenuModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @AppStorage("showMenuBarItem") private var showMenuBar = true
    @AppStorage("showDockIcon") private var showDock = true
    @State private var launchAtLogin = false
    @State private var launchError: String?
    @State private var alertsOn = false
    @State private var alertsLoaded = false
    @State private var alertsError: String?

    private var version: String {
        let i = Bundle.main.infoDictionary
        return "\(i?["CFBundleShortVersionString"] as? String ?? "1.0") (\(i?["CFBundleVersion"] as? String ?? "1"))"
    }

    var body: some View {
        Form {
            accountSection
            menuBarSection
            notificationsSection
            Section("Demo") {
                Toggle("Use demo data", isOn: Binding(get: { model.useDemo }, set: { v in Task { await model.setDemo(v) } }))
                Text("Shows a sample church with four TVs in the menu bar, so you can try the controls without an account.").font(.caption).foregroundStyle(.secondary)
            }
            Section("About") {
                LabeledContent("Church TV OS for Mac", value: version)
                HStack {
                    Link("Help", destination: AppLinks.help)
                    Link("Privacy policy", destination: AppLinks.privacy)
                    Link("Terms", destination: AppLinks.terms)
                    Link("Delete my account", destination: AppLinks.deleteAccount)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 740)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            Task { await model.push.refreshAuthorization(); await loadAlerts() }
        }
        .onChange(of: model.church?.id) { _, _ in Task { await loadAlerts() } }
    }

    // MARK: Account

    private var accountSection: some View {
        Section("Account") {
            if model.isSignedIn {
                LabeledContent("Email", value: model.useDemo ? "Demo (no account)" : (model.user?.email ?? ""))
                if model.churches.count > 1 {
                    Picker("Church", selection: Binding(get: { model.church?.id }, set: { id in
                        if let c = model.churches.first(where: { $0.id == id }) { Task { await model.choose(c) } }
                    })) { ForEach(model.churches) { Text($0.organization.name).tag(Optional($0.id)) } }
                } else {
                    LabeledContent("Church", value: model.church?.organization.name ?? "None")
                }
                LabeledContent("Role", value: model.roleText)
                Button(model.useDemo ? "Leave demo" : "Sign out of Church TV OS", role: .destructive) { Task { await model.signOut() } }
            } else {
                Text("Not signed in. Sign in from the app window.").foregroundStyle(.secondary)
                Button("Open Church TV OS") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
            }
        }
    }

    // MARK: Menu bar

    private var menuBarSection: some View {
        Section("Menu bar and Dock") {
            Toggle("Show menu bar item", isOn: Binding(get: { showMenuBar }, set: { v in
                showMenuBar = v
                if !v && !showDock { setDock(true) }   // never hide both
            }))
            Toggle("Dock icon", isOn: Binding(get: { showDock }, set: { v in
                setDock(v)
                if !v && !showMenuBar { showMenuBar = true }
            }))
            Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
            if let e = launchError { Text(e).font(.caption).foregroundStyle(.red) }
        }
    }

    private func setDock(_ on: Bool) {
        showDock = on
        NSApp.setActivationPolicy(on ? .regular : .accessory)
        if on { NSApp.activate(ignoringOtherApps: true) }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        launchError = nil
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            launchError = "Could not change this: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Notifications

    private var notificationsSection: some View {
        Section("Notifications") {
            Toggle("Alert me when a TV goes offline", isOn: Binding(get: { alertsOn }, set: setAlerts))
                .disabled(!model.isSignedIn || model.useDemo || model.church == nil || !alertsLoaded)
            if let church = model.church, !model.useDemo { Text("For \(church.organization.name). Each person chooses this for themselves.").font(.caption).foregroundStyle(.secondary) }
            if model.useDemo { Text("Turn off demo data and sign in to use alerts.").font(.caption).foregroundStyle(.secondary) }
            if model.push.isDenied {
                HStack {
                    Text("Notifications are off for this app in System Settings.").font(.caption).foregroundStyle(.orange)
                    Button("Open System Settings") {
                        if let u = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(u) }
                    }.controlSize(.small)
                }
            }
            if let e = alertsError ?? model.push.lastError { Text(e).font(.caption).foregroundStyle(.red) }
        }
    }

    private func loadAlerts() async {
        alertsLoaded = false
        guard model.isSignedIn, !model.useDemo else { alertsOn = false; alertsLoaded = true; return }
        alertsOn = await model.offlineAlertsEnabled()
        alertsLoaded = true
    }

    private func setAlerts(_ on: Bool) {
        alertsError = nil
        Task {
            let previous = alertsOn
            alertsOn = on
            if let e = await model.setOfflineAlerts(on) { alertsError = e; alertsOn = previous }
        }
    }
}

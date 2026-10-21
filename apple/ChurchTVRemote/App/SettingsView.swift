import SwiftUI
import ChurchTVCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var alertsOn = false
    @State private var alertsLoaded = false
    @State private var notificationNote: String?
    @State private var confirmSignOut = false

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        List {
            if model.isDemo {
                Section {
                    Label("Demo mode: sample church and sample TVs. Nothing here touches real screens.", systemImage: "sparkles")
                        .foregroundStyle(.orange)
                }
            }

            Section("Church") {
                LabeledContent("Name", value: model.church?.organization.name ?? "")
                LabeledContent("Your role", value: model.church?.role.displayName ?? "")
                if let mods = model.church?.modules, !mods.isEmpty {
                    LabeledContent("Modules", value: mods.map(\.displayName).joined(separator: ", "))
                }
                if model.churches.count > 1 {
                    Button("Switch church") { model.switchChurch() }
                }
            }

            Section {
                Toggle("TV offline alerts", isOn: Binding(get: { alertsOn }, set: { setAlerts($0) }))
                    .disabled(!alertsLoaded)
                if model.push.isDenied && !model.isDemo {
                    Button("Open iOS Settings to allow notifications") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
                if let n = notificationNote { Text(n).font(.footnote).foregroundStyle(.red) }
            } header: { Text("Notifications") } footer: {
                Text("Get a notification when a TV goes offline during a scheduled time. iOS asks for permission the first time you turn this on.")
            }

            Section("Account") {
                if let email = model.user?.email { LabeledContent("Signed in as", value: email) }
                Button("Sign out", role: .destructive) { confirmSignOut = true }
                if !model.isDemo { Link("Delete account (website)", destination: Config.deleteAccountURL) }
            }

            Section("About") {
                LabeledContent("Version", value: version)
                LabeledContent("Mode", value: model.isDemo ? "Demo" : "Live")
                Link("Church TV OS website", destination: Config.websiteURL)
                Link("Privacy policy", destination: Config.privacyURL)
                Link("Terms of use", destination: Config.termsURL)
            }
        }
        .navigationTitle("Settings")
        .task(id: model.church?.id) {
            await model.push.refreshAuthorization()
            alertsOn = await model.offlineAlertsEnabled() && (model.isDemo || model.push.isAuthorized)
            alertsLoaded = true
        }
        .confirmationDialog("Sign out?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await model.signOut() } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func setAlerts(_ on: Bool) {
        let previous = alertsOn
        alertsOn = on
        notificationNote = nil
        Task {
            if let problem = await model.setOfflineAlerts(on) {
                alertsOn = previous
                notificationNote = problem
            }
        }
    }
}

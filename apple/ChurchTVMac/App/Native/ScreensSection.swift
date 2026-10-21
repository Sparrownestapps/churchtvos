import SwiftUI
import ChurchTVCore

/// Support data for the Screens pages: locations, groups, signage playlists, settings per screen, plan limit.
@MainActor
@Observable
final class ScreensSupport {
    var settings: [UUID: ScreenSettings] = [:]
    var locations: [Location] = []
    var sites: [Site] = []
    var groups: [ScreenGroup] = []
    var signagePlaylists: [PlaylistRef] = []
    var limit: Int?
    var error: String?

    func load(_ model: MenuModel) async {
        guard let church = model.church, let ops = model.ops else { return }
        let org = church.id
        async let s = try? ops.loadScreenSettings(organizationId: org)
        async let l = try? model.service.listLocations(organizationId: org)
        async let si = try? model.service.listSites(organizationId: org)
        async let g = try? model.service.listScreenGroups(organizationId: org)
        async let t = try? ops.tvLimit(organizationId: org)
        let signage: [Playlist]? = church.modules.contains(.signage) ? try? await model.service.listPlaylists(kind: .signage, organizationId: org) : nil
        let (settings, locations, sites, groups, limit) = await (s, l, si, g, t)
        if let settings { self.settings = settings }
        if let locations { self.locations = locations.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
        if let sites { self.sites = sites }
        if let groups { self.groups = groups }
        self.limit = limit ?? nil
        self.signagePlaylists = signage?.map { PlaylistRef(id: $0.id, name: $0.name) } ?? []
        if settings == nil { error = "Could not load screen details." } else { error = nil }
    }

    func locationLabel(_ id: UUID?) -> String {
        guard let id, let l = locations.first(where: { $0.id == id }) else { return "No location" }
        let site = l.siteId.flatMap { sid in sites.first { $0.id == sid }?.name }
        return site.map { sites.count > 1 ? "\(l.name) · \($0)" : l.name } ?? l.name
    }
}

struct ScreensSection: View {
    @Environment(MenuModel.self) private var model
    @State private var nav = NavState.shared
    @State private var support = ScreensSupport()

    private var canManage: Bool { model.church.map { ScreenRules.canManage($0.role) } ?? false }

    var body: some View {
        HSplitView {
            list.frame(minWidth: 300, idealWidth: 340, maxWidth: 440)
            Group {
                if let s = model.selectedScreen {
                    ScreenDetailView(screen: s, support: support, canManage: canManage).id("\(s.id)-\(model.screensRevision)")
                } else {
                    ContentUnavailableView("No screens yet", systemImage: "tv", description: Text(canManage ? "Pair a TV with the code it shows." : "Ask a church admin to pair a TV."))
                }
            }
            .frame(minWidth: 380, maxWidth: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { nav.showPairSheet = true } label: { Label("Pair a TV", systemImage: "plus") }
                    .disabled(!canManage).help(canManage ? "Pair a new TV (⌥⌘N)" : "Only owners and admins can pair TVs")
            }
        }
        .sheet(isPresented: $nav.showPairSheet) { PairScreenSheet(support: support) }
        .task(id: model.screensRevision) { await support.load(model) }
    }

    private var list: some View {
        VStack(spacing: 0) {
            HStack {
                Text(ScreenRules.countLine(screens: model.screens.count, limit: support.limit)).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            List(selection: Binding(get: { model.selectedScreenId }, set: { model.selectedScreenId = $0 })) {
                ForEach(model.screens) { s in ScreenListRow(screen: s).tag(s.id) }
            }
            .listStyle(.inset)
            .overlay { if model.screens.isEmpty { Text(model.loadError ?? "No TVs paired to this church yet.").foregroundStyle(.secondary) } }
        }
    }
}

private struct ScreenListRow: View {
    let screen: ScreenInfo
    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(screen.isOnline() ? Color.green : Color.red).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(screen.screen.displayName).font(.body.weight(.medium)).lineLimit(1)
                Text(screen.locationLine.isEmpty ? "No location" : screen.locationLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(NowPlaying.line(screen)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            StateChip(state: screen.displayState())
        }
        .padding(.vertical, 3)
    }
}

/// "Sunday 10:30 Service · Slide 4 of 16" or why nothing is showing.
enum NowPlaying {
    static func line(_ screen: ScreenInfo) -> String {
        if !screen.isOnline() { return "Offline · last seen \(Formatting.ago(screen.screen.lastSeenAt))" }
        guard let st = screen.status, st.state != .idle else { return "Nothing playing" }
        var parts: [String] = []
        if let t = st.title, !t.isEmpty { parts.append(t) }
        if let n = st.slideText { parts.append(n) }
        return parts.isEmpty ? st.state.label : parts.joined(separator: " · ")
    }
}

// MARK: - Detail and editing

private struct ScreenDetailView: View {
    @Environment(MenuModel.self) private var model
    let screen: ScreenInfo
    let support: ScreensSupport
    let canManage: Bool

    @State private var draft: ScreenSettings?
    @State private var original: ScreenSettings?
    @State private var saving = false
    @State private var error: String?
    @State private var saved = false
    @State private var confirmUnpair = false

    private var changed: Bool { draft != original }
    private var modules: [ModuleDef] { model.moduleRegistry.isEmpty ? AppModule.allCases.map { ModuleDef(id: $0.rawValue, name: $0.displayName) } : model.moduleRegistry }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                nowPlaying
                if canManage, draft != nil { editor } else { facts }
            }
            .padding(20).frame(maxWidth: 640, alignment: .leading)
        }
        .onAppear(perform: syncDraft)
        .onChange(of: support.settings) { _, _ in if !changed { syncDraft() } }
        .confirmationDialog("Remove \(screen.screen.displayName)?", isPresented: $confirmUnpair, titleVisibility: .visible) {
            Button("Remove / unpair", role: .destructive) { unpair() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The TV will forget this church and show a new pairing code.") }
    }

    private func syncDraft() {
        if let s = support.settings[screen.id] { draft = s; original = s }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(screen.screen.displayName).font(.title2.weight(.semibold))
                Text("\(screen.isOnline() ? "Online" : "Offline") · seen \(Formatting.ago(screen.screen.lastSeenAt))").foregroundStyle(.secondary)
            }
            Spacer()
            StateChip(state: screen.displayState())
        }
    }

    private var nowPlaying: some View {
        GroupBox("Now playing") {
            VStack(alignment: .leading, spacing: 6) {
                Text(NowPlaying.line(screen)).frame(maxWidth: .infinity, alignment: .leading)
                if let st = screen.status, st.state != .idle, screen.isOnline() {
                    if let label = st.itemLabel, !label.isEmpty { Text(label).font(.callout).foregroundStyle(.secondary) }
                    if st.slideCount != nil { ProgressView(value: st.progress) }
                }
                if !screen.supportsRemote { Text("Update the TV app to 1.5.0 or newer for remote control.").font(.caption).foregroundStyle(.orange) }
            }.padding(4)
        }
    }

    private var facts: some View {
        GroupBox("Details") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                fact("Location", screen.locationLine.isEmpty ? "No location" : screen.locationLine)
                fact("Orientation", ScreenOrientation(rawValue: screen.screen.orientation ?? "")?.displayName ?? "Landscape")
                fact("Default", defaultName(screen.screen.defaultModule))
                fact("App", [screen.screen.appVersion.map { "v\($0)" }, screen.screen.model].compactMap { $0 }.joined(separator: " · "))
            }.padding(4)
        }
    }

    private func fact(_ k: String, _ v: String) -> some View {
        GridRow { Text(k).foregroundStyle(.secondary); Text(v.isEmpty ? "-" : v) }
    }

    private func defaultName(_ id: String?) -> String { id == "off" ? "Off (black screen)" : model.moduleName(id ?? "kids") }

    @ViewBuilder private var editor: some View {
        let binding = Binding<ScreenSettings>(get: { draft ?? ScreenSettings(screenId: screen.id) }, set: { draft = $0 })
        GroupBox("Settings") {
            Form {
                TextField("Name", text: Binding(get: { binding.wrappedValue.name ?? "" }, set: { binding.wrappedValue.name = $0 }))
                Picker("Location", selection: Binding(get: { binding.wrappedValue.locationId }, set: { binding.wrappedValue.locationId = $0 })) {
                    Text("None").tag(UUID?.none)
                    ForEach(support.locations) { Text(support.locationLabel($0.id)).tag(Optional($0.id)) }
                }
                Picker("Orientation", selection: binding.orientation) { ForEach(ScreenOrientation.allCases) { Text($0.displayName).tag($0) } }
                Picker("Default module", selection: binding.defaultModule) {
                    ForEach(modules) { Text($0.name).tag($0.id) }
                    Text("Off (black screen)").tag("off")
                }
                Picker("Group", selection: Binding(get: { binding.wrappedValue.groupId }, set: { binding.wrappedValue.groupId = $0 })) {
                    Text("None").tag(UUID?.none)
                    ForEach(support.groups) { Text($0.name).tag(Optional($0.id)) }
                }
                if model.church?.modules.contains(.signage) == true {
                    Picker("Signage default playlist", selection: Binding(get: { binding.wrappedValue.signageDefaultPlaylistId }, set: { binding.wrappedValue.signageDefaultPlaylistId = $0 })) {
                        Text("None (black screen)").tag(UUID?.none)
                        ForEach(support.signagePlaylists) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                Toggle("Start playing automatically", isOn: binding.autoplay)
                Text("Kids and Slides begin the scheduled content by themselves, for example after a power cut (Signage always plays on its own). Needs TV app 1.4.0 or newer.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .formStyle(.columns).padding(6)
        }
        if (draft?.orientation ?? .landscape) != .landscape { Text(ScreenRules.portraitNote).font(.callout).foregroundStyle(.secondary) }
        if let e = error { Text(e).foregroundStyle(.red) }
        HStack {
            Button("Save changes") { save() }.keyboardShortcut("s").buttonStyle(.borderedProminent).disabled(!changed || saving)
            if changed { Button("Revert") { draft = original; error = nil } }
            if saved && !changed { Label("Saved", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            Spacer()
            Button("Remove / unpair…", role: .destructive) { confirmUnpair = true }
        }
    }

    private func save() {
        guard let d = draft else { return }
        saving = true; error = nil
        Task {
            defer { saving = false }
            do {
                try await model.ops?.updateScreen(d)
                original = d; saved = true
                await model.screensChanged()
            } catch { self.error = Formatting.message(for: error) }
        }
    }

    private func unpair() {
        Task {
            do { try await model.ops?.releaseScreen(id: screen.id); model.selectedScreenId = nil; await model.screensChanged() }
            catch { self.error = Formatting.message(for: error) }
        }
    }
}

// MARK: - Pair a TV

struct PairScreenSheet: View {
    @Environment(MenuModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let support: ScreensSupport
    @State private var code = ""
    @State private var locationId: UUID?
    @State private var name = ""
    @State private var busy = false
    @State private var error: String?
    @State private var done: String?

    private var atLimit: Bool { ScreenRules.atLimit(screens: model.screens.count, limit: support.limit) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pair a TV").font(.title2.weight(.semibold))
            Text("Open the Church TV OS app on the TV. It shows a 6-character code; enter it here and choose where the TV is.").foregroundStyle(.secondary)
            if model.useDemo { Text("Demo: the sample TV shows the code \(DemoPairing.code).").font(.callout).foregroundStyle(.orange) }
            Form {
                TextField("Code on the TV", text: Binding(get: { code }, set: { code = PairingCode.display($0) }), prompt: Text("ABC 123"))
                    .font(.system(.title3, design: .monospaced))
                Picker("Location", selection: $locationId) {
                    Text("Choose…").tag(UUID?.none)
                    ForEach(support.locations) { Text(support.locationLabel($0.id)).tag(Optional($0.id)) }
                }
                TextField("Name (optional)", text: $name, prompt: Text("e.g. Lobby left"))
            }
            .formStyle(.columns)
            if support.locations.isEmpty { Text("Add a location under Sites & Locations first.").font(.callout).foregroundStyle(.secondary) }
            if atLimit { Text("Your plan allows \(support.limit ?? 0) TV(s). Remove a TV or upgrade to add more.").font(.callout).foregroundStyle(.orange) }
            if let error { Text(error).foregroundStyle(.red) }
            if let done { Label(done, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            HStack {
                Spacer()
                Button(done == nil ? "Cancel" : "Done") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Pair TV") { pair() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(busy || !PairingCode.isComplete(code) || locationId == nil || done != nil)
            }
        }
        .padding(22).frame(width: 440)
    }

    private func pair() {
        guard let locationId else { return }
        busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                try await model.ops?.claimScreen(code: code, locationId: locationId, name: name)
                done = "Paired with \(support.locationLabel(locationId)). The TV will update in a few seconds."
                code = ""; name = ""
                await model.screensChanged()
            } catch { self.error = Formatting.message(for: error) }
        }
    }
}

enum DemoPairing { static let code = "DEM 123" }

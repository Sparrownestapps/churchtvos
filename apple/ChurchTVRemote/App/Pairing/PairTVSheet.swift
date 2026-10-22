import SwiftUI
import UIKit
import ChurchTVCore
import ChurchTVEditors

/// State of one pairing attempt. Kept out of the view so it can be tested.
@MainActor
@Observable
final class PairingFlow {
    var code = ""                       // shown as "ABC 123"
    var name = ""
    var locationId: UUID?
    var locations: [Location] = []
    var sites: [Site] = []
    var limit: Int?
    var busy = false
    var error: String?
    var scanHint: String?               // "That QR code is not a Church TV OS code"
    var scannedCode = false             // the code came from the camera
    var pairedName: String?
    var pairedLocation: String?
    /// "+ New room…" chosen: the form for a new room (and site) is showing.
    var creatingRoom = false
    var draft = NewRoomDraft()
    private var allLocations: [Location] = []

    var normalizedCode: String? { PairingCode.parseTyped(code) }
    var canSubmit: Bool {
        normalizedCode != nil && !busy && pairedName == nil && (creatingRoom ? roomProblem == nil : locationId != nil)
    }
    var roomProblem: String? { roomProblem(role: role) }
    private var role: Role = .admin
    private func roomProblem(role: Role) -> String? { RoomRules.problem(draft, role: role, sites: sites, locations: allLocations) }
    /// The message to show under the room form once the user has typed something (not while it is still blank).
    var roomHint: String? { draft.name.isEmpty && draft.newSiteName.isEmpty ? nil : roomProblem }

    /// Tag for the location picker: the "+ New room…" row while creating.
    var pickerSelection: UUID? { creatingRoom ? RoomRules.newRoomTag : locationId }
    func pick(_ id: UUID?) {
        if id == RoomRules.newRoomTag { creatingRoom = true; error = nil } else { creatingRoom = false; locationId = id }
    }
    func beginNewRoom(church: ChurchAccess) {
        if !creatingRoom || draft.modules.isEmpty && draft.name.isEmpty {
            draft = RoomRules.initialDraft(churchModules: church.modules, sites: sites)
        }
        creatingRoom = true
    }
    var siteSelection: UUID? { draft.creatingSite ? RoomRules.newSiteTag : draft.siteId }
    func pickSite(_ id: UUID?) {
        if id == RoomRules.newSiteTag { draft.creatingSite = true; draft.siteId = nil } else { draft.creatingSite = false; draft.siteId = id }
    }

    func locationLabel(_ l: Location) -> String {
        let site = l.siteId.flatMap { id in sites.first { $0.id == id }?.name }
        return site.map { sites.count > 1 ? "\(l.name) · \($0)" : l.name } ?? l.name
    }

    /// Typed or pasted text: a pasted pairing link works too.
    func setTyped(_ text: String) {
        scannedCode = false
        code = PairingCode.display(PairingCode.parse(text) ?? text)
        if error != nil { error = nil }
    }

    /// A scanned QR string. Returns true when it was a pairing code (the caller stops the camera and gives haptic feedback).
    func handleScan(_ text: String) -> Bool {
        guard let c = PairingCode.parse(text) else {
            scanHint = "That QR code is not a TV pairing code. Scan the code shown on the TV."
            return false
        }
        code = PairingCode.display(c); scannedCode = true; scanHint = nil; error = nil
        return true
    }

    func load(model: AppModel) async {
        guard let church = model.church else { return }
        async let l = try? model.service.listLocations(organizationId: church.id)
        async let s = try? model.service.listSites(organizationId: church.id)
        async let t = try? model.ops?.tvLimit(organizationId: church.id)
        let (locs, sites, limit) = await (l, s, t)
        self.sites = sites ?? []
        allLocations = locs ?? []
        role = church.role
        locations = ScreenRules.pairableLocations(role: church.role, siteIds: church.siteIds, locations: locs ?? [])
        self.limit = limit ?? nil
        if locationId == nil || !locations.contains(where: { $0.id == locationId }) { locationId = locations.count == 1 ? locations.first?.id : nil }
    }

    func submit(model: AppModel) async {
        guard let code = normalizedCode, let ops = model.ops else {
            if model.ops == nil { error = "Pairing is not available here." }
            return
        }
        guard creatingRoom || locationId != nil else { return }
        busy = true; error = nil
        defer { busy = false }
        let before = Set(model.screens.map(\.id))
        let tvName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var pairedInto = locationId
        if creatingRoom, let church = model.church {
            if let p = roomProblem { error = p; return }
            let result = await RoomPairing.run(ops: ops, organizationId: church.id, code: code, tvName: tvName.isEmpty ? nil : tvName, draft: draft, existingSite: nil)
            // Keep whatever was created, and select it, so a retry does not duplicate it.
            if let site = result.site { sites.append(site); draft.siteId = site.id; draft.creatingSite = false }
            if let loc = result.location {
                allLocations.append(loc); locations.append(loc)
                locations.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                locationId = loc.id; creatingRoom = false; pairedInto = loc.id
            }
            if !result.paired { error = result.message; return }
            await finishPairing(model: model, before: before, locationId: pairedInto, tvName: tvName)
            return
        }
        guard let locationId else { return }
        do {
            try await ops.claimScreen(code: code, locationId: locationId, name: tvName)
            await finishPairing(model: model, before: before, locationId: locationId, tvName: tvName)
        } catch {
            self.error = ScreenRules.pairingMessage(for: error)
        }
    }

    private func finishPairing(model: AppModel, before: Set<UUID>, locationId: UUID?, tvName: String) async {
        await model.refreshScreens()
        let new = model.screens.first { !before.contains($0.id) }
        pairedName = new?.screen.displayName ?? (tvName.isEmpty ? "Your TV" : tvName)
        pairedLocation = locations.first { $0.id == locationId }.map(locationLabel)
        if let new { model.selectedScreenId = new.id }
    }
}

struct PairTVSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var flow = PairingFlow()
    @State private var camera: CameraAccess = .checking
    @State private var scanning = false
    @State private var torch = false
    @FocusState private var codeFocused: Bool

    /// DEBUG screenshots of the new-room form hide the intro and camera rows so the form fits on screen.
    private var debugCompact: Bool {
        #if DEBUG
        return model.debugNewRoom != nil
        #else
        return false
        #endif
    }

    private var atLimit: Bool { ScreenRules.atLimit(screens: model.screens.count, limit: flow.limit) }

    var body: some View {
        NavigationStack {
            Group {
                if flow.pairedName != nil { success } else { form }
            }
            .navigationTitle("Pair a TV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(flow.pairedName == nil ? "Cancel" : "Done") { dismiss() } }
            }
        }
        .task {
            await flow.load(model: model)
            #if DEBUG
            if let fake = model.debugPairCamera { camera = fake == "denied" ? .denied : fake == "camera" ? .ready : .unavailable }
            else { camera = await CameraAccess.resolve() }
            if let text = model.debugPairScan { _ = flow.handleScan(text) }
            if let room = model.debugNewRoom, let church = model.church {
                flow.pick(RoomRules.newRoomTag); flow.beginNewRoom(church: church); flow.draft.name = room
                if let site = model.debugNewSite { flow.pickSite(RoomRules.newSiteTag); flow.draft.newSiteName = site }
            }
            if model.debugPairSubmit, !flow.creatingRoom { if flow.locationId == nil { flow.locationId = flow.locations.first?.id } }
            if model.debugPairSubmit, flow.canSubmit { await flow.submit(model: model) }
            #else
            camera = await CameraAccess.resolve()
            #endif
            scanning = camera == .ready && flow.normalizedCode == nil
        }
        .interactiveDismissDisabled(flow.busy)
    }

    // MARK: Form

    private var form: some View {
        Form {
            if let e = flow.error { Section { Banner(text: e, style: .error) } }
            if !debugCompact { Section {
                Text("Open the Church TV OS app on the TV. It shows a QR code and a 6-character code. Scan the QR code or type the code.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if model.isDemo {
                    Button { flow.setTyped("DEM 723") } label: { Label("Demo: use the sample TV's code (DEM 723)", systemImage: "sparkles") }
                }
            } }
            if !debugCompact { scanSection }
            Section("Code") {
                TextField("TFW K5H", text: Binding(get: { flow.code }, set: { flow.setTyped($0) }))
                    .font(.system(.title2, design: .monospaced).weight(.semibold))
                    .textInputAutocapitalization(.characters).autocorrectionDisabled().keyboardType(.asciiCapable)
                    .focused($codeFocused)
                    .accessibilityLabel("Pairing code")
                if flow.scannedCode, flow.normalizedCode != nil {
                    Label("Scanned from the TV", systemImage: "qrcode.viewfinder").font(.caption).foregroundStyle(.green)
                } else if !flow.code.isEmpty, flow.normalizedCode == nil, PairingCode.normalize(flow.code).count >= PairingCode.length {
                    Text("Codes use the letters A to Z (no I, L, O) and the digits 2 to 9. Check the code on the TV.").font(.caption).foregroundStyle(.orange)
                }
            }
            Section {
                TextField("Name (optional), e.g. Lobby left", text: Binding(get: { flow.name }, set: { flow.name = $0 }))
                Picker("Location", selection: Binding(get: { flow.pickerSelection }, set: { flow.pick($0); if $0 == RoomRules.newRoomTag, let c = model.church { flow.beginNewRoom(church: c) } })) {
                    Text("Choose…").tag(UUID?.none)
                    ForEach(flow.locations) { Text(flow.locationLabel($0)).tag(Optional($0.id)) }
                    if model.canPair { Text("+ New room…").tag(Optional(RoomRules.newRoomTag)) }
                }
            } footer: {
                if flow.locations.isEmpty && !model.canPair { Text("There is no location you can pair into yet. Ask a church admin to add one.") }
            }
            if flow.creatingRoom { newRoomSection }
            Section {
                if atLimit {
                    Banner(text: "Your plan allows \(flow.limit ?? 0) TV(s). Remove a TV or upgrade to add more.", style: .warning)
                }
                Button { codeFocused = false; Task { await flow.submit(model: model) } } label: {
                    HStack {
                        Spacer()
                        if flow.busy { ProgressView().padding(.trailing, 6) }
                        Text(flow.busy ? "Pairing…" : "Pair TV").font(.headline)
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent).disabled(!flow.canSubmit)
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// Fields for a new room (and a new site when needed). Shown under the location picker after "+ New room…".
    @ViewBuilder private var newRoomSection: some View {
        Section {
            TextField("Room name, e.g. Nursery", text: Binding(get: { flow.draft.name }, set: { flow.draft.name = $0 }))
                .accessibilityLabel("Room name")
            Picker("Site", selection: Binding(get: { flow.siteSelection }, set: { flow.pickSite($0) })) {
                if flow.sites.count != 1 && !flow.draft.creatingSite { Text("Choose…").tag(UUID?.none) }
                ForEach(flow.sites) { Text($0.name).tag(Optional($0.id)) }
                Text("+ New site…").tag(Optional(RoomRules.newSiteTag))
            }
            if flow.draft.creatingSite {
                TextField("Site name, e.g. East Campus", text: Binding(get: { flow.draft.newSiteName }, set: { flow.draft.newSiteName = $0 }))
                    .accessibilityLabel("Site name")
                Picker("Time zone", selection: Binding(get: { flow.draft.newSiteTimeZone }, set: { flow.draft.newSiteTimeZone = $0 })) {
                    ForEach(timeZoneChoices, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) }
                }
            }
            ForEach(AppModule.allCases) { m in
                Toggle(m.displayName, isOn: Binding(get: { flow.draft.modules.contains(m.rawValue) }, set: { on in
                    if on { flow.draft.modules.insert(m.rawValue) } else { flow.draft.modules.remove(m.rawValue) }
                }))
            }
        } header: { Text("New room")
        } footer: {
            if let hint = flow.roomHint { Text(hint).foregroundStyle(.orange) }
            else { Text("The room is created first, then the TV is paired into it. Tags choose which applications use this room.") }
        }
    }

    private var timeZoneChoices: [String] {
        var ids = TimeZone.knownTimeZoneIdentifiers
        if !ids.contains(flow.draft.newSiteTimeZone) { ids.append(flow.draft.newSiteTimeZone) }
        return ids.sorted()
    }

    @ViewBuilder private var scanSection: some View {
        switch camera {
        case .checking:
            EmptyView()
        case .unavailable:
            Section { Label("No camera available here. Type the code below.", systemImage: "camera.slash").font(.subheadline).foregroundStyle(.secondary) }
        case .denied:
            Section {
                Label("Camera access is off, so the QR code cannot be scanned.", systemImage: "camera.fill").font(.subheadline)
                Button("Open Settings to allow the camera") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                Text("You can still type the code below.").font(.caption).foregroundStyle(.secondary)
            }
        case .ready:
            Section {
                if scanning {
                    ZStack(alignment: .topTrailing) {
                        QRScannerView(torchOn: torch) { text in
                            if flow.handleScan(text) {
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                scanning = false; torch = false
                            }
                        }
                        .frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.7), lineWidth: 2).padding(40) }
                        .accessibilityLabel("Camera view. Point at the QR code on the TV.")
                        if deviceHasTorch {
                            Button { torch.toggle() } label: {
                                Image(systemName: torch ? "flashlight.on.fill" : "flashlight.off.fill").padding(10)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                            .padding(10).accessibilityLabel(torch ? "Turn the light off" : "Turn the light on")
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    if let hint = flow.scanHint { Text(hint).font(.caption).foregroundStyle(.orange) }
                } else {
                    Button { flow.scanHint = nil; scanning = true } label: { Label(flow.scannedCode ? "Scan again" : "Scan QR code", systemImage: "qrcode.viewfinder") }
                }
            }
        }
    }

    // MARK: Success

    private var success: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.system(size: 72)).foregroundStyle(.green)
            Text("TV paired").font(.title.weight(.semibold))
            VStack(spacing: 4) {
                Text(flow.pairedName ?? "").font(.title3)
                if let loc = flow.pairedLocation { Text(loc).foregroundStyle(.secondary) }
            }
            Text("It will show up in your screens in a few seconds.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
            Button { dismiss() } label: { Text("Done").font(.headline).frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .padding(24)
        .onAppear { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        .accessibilityElement(children: .combine)
    }
}

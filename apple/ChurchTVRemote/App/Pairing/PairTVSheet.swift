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

    var normalizedCode: String? { PairingCode.parseTyped(code) }
    var canSubmit: Bool { normalizedCode != nil && locationId != nil && !busy && pairedName == nil }

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
        locations = ScreenRules.pairableLocations(role: church.role, siteIds: church.siteIds, locations: locs ?? [])
        self.limit = limit ?? nil
        if locationId == nil || !locations.contains(where: { $0.id == locationId }) { locationId = locations.count == 1 ? locations.first?.id : nil }
    }

    func submit(model: AppModel) async {
        guard let code = normalizedCode, let locationId, let ops = model.ops else {
            if model.ops == nil { error = "Pairing is not available here." }
            return
        }
        busy = true; error = nil
        defer { busy = false }
        let before = Set(model.screens.map(\.id))
        do {
            try await ops.claimScreen(code: code, locationId: locationId, name: name.trimmingCharacters(in: .whitespacesAndNewlines))
            await model.refreshScreens()
            let new = model.screens.first { !before.contains($0.id) }
            pairedName = new?.screen.displayName ?? (name.isEmpty ? "Your TV" : name)
            pairedLocation = locations.first { $0.id == locationId }.map(locationLabel)
            if let new { model.selectedScreenId = new.id }
        } catch {
            self.error = ScreenRules.pairingMessage(for: error)
        }
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
            if model.debugPairSubmit { if flow.locationId == nil { flow.locationId = flow.locations.first?.id } }
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
            Section {
                Text("Open the Church TV OS app on the TV. It shows a QR code and a 6-character code. Scan the QR code or type the code.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if model.isDemo {
                    Button { flow.setTyped("DEM 723") } label: { Label("Demo: use the sample TV's code (DEM 723)", systemImage: "sparkles") }
                }
            }
            scanSection
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
                Picker("Location", selection: Binding(get: { flow.locationId }, set: { flow.locationId = $0 })) {
                    Text("Choose…").tag(UUID?.none)
                    ForEach(flow.locations) { Text(flow.locationLabel($0)).tag(Optional($0.id)) }
                }
            } footer: {
                if flow.locations.isEmpty { Text("There is no location you can pair into yet. Add a location in Sites & Locations on the website first.") }
            }
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

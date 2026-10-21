import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ChurchTVCore

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        self.init(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    /// "#rrggbb" in sRGB.
    var hexString: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return String(format: "#%02x%02x%02x", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
    }
}

/// Church settings and branding (the website's Settings page): name, logos, colours per module, splash, YouTube channel, plan.
struct ChurchSettingsSection: View {
    @Environment(MenuModel.self) private var model
    @State private var original: OrganizationSettings?
    @State private var name = ""
    @State private var branding = BrandingSettings()
    @State private var channel = ""
    @State private var scope: BrandScope = .church
    @State private var plan: [PlanRow] = []
    @State private var loadError: String?
    @State private var saving = false
    @State private var saved = false
    @State private var uploading = false
    @State private var error: String?

    private var changed: Bool {
        guard let o = original else { return false }
        return name != o.name || channel.trimmingCharacters(in: .whitespaces) != (o.branding.youtubeChannelId ?? "") || stripped(branding) != o.branding
    }
    private func stripped(_ b: BrandingSettings) -> BrandingSettings { var x = b; x.youtubeChannelId = original?.branding.youtubeChannelId; return x }
    private var allowed: Bool { model.church.map { PeopleRules.canManage($0.role) } ?? false }

    private var scopes: [BrandScope] {
        BrandScope.allCases.filter { sc in
            guard let m = sc.module else { return true }
            return model.moduleRegistry.isEmpty || model.moduleRegistry.contains { $0.id == m.rawValue }
        }
    }

    var body: some View {
        Group {
            if !allowed {
                ContentUnavailableView("Owners and admins only", systemImage: "lock", description: Text("Ask a church admin to change settings."))
            } else if original == nil {
                if let loadError { Text(loadError).foregroundStyle(.red) } else { ProgressView() }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        churchBox
                        brandingBox
                        youtubeBox
                        planBox
                    }
                    .padding(22).frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
                }
                .safeAreaInset(edge: .bottom) { saveBar }
            }
        }
        .task { await load() }
    }

    private var saveBar: some View {
        HStack {
            if let error { Text(error).foregroundStyle(.red).lineLimit(2) }
            if saved && !changed { Label("Saved", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            Spacer()
            if changed { Button("Revert") { revert() } }
            Button("Save settings") { save() }.keyboardShortcut("s").buttonStyle(.borderedProminent).disabled(!changed || saving)
        }
        .padding(.horizontal, 22).padding(.vertical, 10).background(.bar)
    }

    private var churchBox: some View {
        GroupBox("Church") {
            Form {
                TextField("Name", text: $name)
                LabeledContent("Web address name", value: original?.slug ?? "")
            }.formStyle(.columns).padding(6)
        }
    }

    private var brandingBox: some View {
        GroupBox("Branding") {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Look for", selection: $scope) { ForEach(scopes) { Text($0.title).tag($0) } }.pickerStyle(.segmented).labelsHidden()
                if scope != .church { Text("Anything you leave alone follows the church's look.").font(.callout).foregroundStyle(.secondary) }
                logoRow("Logo", "Shown on light backgrounds (the pairing and home screens).", dark: false)
                logoRow("Logo for dark backgrounds", "Optional. Used on the full-screen splash and on dark colours. Falls back to the logo above.", dark: true)
                colours
                splash
                preview
            }.padding(8)
        }
    }

    private var own: BrandLook { branding.look(scope) }
    private var eff: BrandingSettings.Effective { branding.effective(scope) }

    private func logoRow(_ title: String, _ hint: String, dark: Bool) -> some View {
        let url = dark ? own.logoDarkURL : own.logoURL
        let inherited = scope != .church && url == nil ? (dark ? branding.look(.church).logoDarkURL : branding.look(.church).logoURL) : nil
        return VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.medium))
            HStack(spacing: 12) {
                logoThumb(url ?? inherited, dark: dark)
                Button(uploading ? "Uploading…" : (url == nil ? "Choose image…" : "Replace…")) { chooseLogo(dark: dark) }.disabled(uploading)
                if url != nil { Button(scope == .church ? "Remove" : "Use church logo") { branding.update(scope) { if dark { $0.logoDarkURL = nil } else { $0.logoURL = nil } } }.buttonStyle(.link) }
            }
            Text((inherited != nil ? "Using the church logo. " : "") + hint).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func logoThumb(_ url: String?, dark: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(dark ? Color(hex: "#1b2a4a") : .white).overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            if let url, DemoMedia.parse(url) == nil, let u = URL(string: url) {
                AsyncImage(url: u) { $0.resizable().scaledToFit() } placeholder: { ProgressView().controlSize(.small) }.padding(6)
            } else if url != nil {
                Image(systemName: "photo").foregroundStyle(.secondary)
            } else {
                Text("None").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(width: 120, height: 56)
    }

    private var colours: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Colours").font(.subheadline.weight(.medium))
            if scope != .church {
                Toggle("Use different colours for \(scope.title)", isOn: Binding(
                    get: { ColorTools.isHex(own.primaryColor) || ColorTools.isHex(own.accentColor) },
                    set: { on in branding.update(scope) { if on { $0.primaryColor = eff.primary; $0.accentColor = eff.accent } else { $0.primaryColor = nil; $0.accentColor = nil } } }))
            }
            if scope == .church || ColorTools.isHex(own.primaryColor) || ColorTools.isHex(own.accentColor) {
                HStack(spacing: 18) {
                    ColorPicker("Primary", selection: Binding(get: { Color(hex: eff.primary) }, set: { c in branding.update(scope) { $0.primaryColor = c.hexString } }))
                    ColorPicker("Accent", selection: Binding(get: { Color(hex: eff.accent) }, set: { c in branding.update(scope) { $0.accentColor = c.hexString } }))
                    Button("Reset colours") {
                        branding.update(scope) { $0.primaryColor = scope == .church ? BrandingSettings.defaultPrimary : eff.primary; $0.accentColor = scope == .church ? BrandingSettings.defaultAccent : eff.accent }
                    }.buttonStyle(.link)
                }
            }
        }
    }

    private var splash: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Full-screen logo splash").font(.subheadline.weight(.medium))
            Toggle("Show the logo full screen when the TV starts" + (scope == .church ? " or switches module" : " or switches to this module"),
                   isOn: Binding(get: { eff.splashEnabled }, set: { on in branding.update(scope) { $0.splashEnabled = on } }))
            if eff.splashEnabled {
                Stepper(value: Binding(get: { eff.splashSeconds }, set: { n in branding.update(scope) { $0.splashEnabled = true; $0.splashSeconds = BrandingSettings.clampSplashSeconds(n) } }),
                        in: BrandingSettings.splashRange) { Text("Seconds on screen: \(eff.splashSeconds)") }
            }
        }
    }

    /// Mock-ups of what a TV shows with these settings.
    private var preview: some View {
        let e = eff
        let light = ColorTools.luminance(e.primary) > 0.45
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                tv(bg: Color(hex: e.primary), tag: "Splash") { Text(name.uppercased()).font(.caption.bold()).foregroundStyle(.white) }
                tv(bg: .white, tag: "Pairing / home") {
                    VStack(spacing: 4) {
                        Text("Pair this TV").font(.caption.bold()).foregroundStyle(Color(hex: e.primary))
                        Text("RJH CM5").font(.caption2.monospaced()).padding(.horizontal, 6).padding(.vertical, 2).background(Color(hex: e.primary)).foregroundStyle(.white)
                    }
                }
                tv(bg: Color(hex: e.primary), tag: "Countdown") {
                    VStack(spacing: 2) {
                        Text("SERVICE STARTS IN").font(.system(size: 7, weight: .bold)).foregroundStyle(Color(hex: e.accent))
                        Text("4:59").font(.title3.bold().monospacedDigit()).foregroundStyle(.white)
                    }
                }
            }
            if light { Text("This primary colour is quite light. White text on the TV countdown and lyrics screens may be hard to read.").font(.caption).foregroundStyle(.orange) }
        }
    }

    private func tv<C: View>(bg: Color, tag: String, @ViewBuilder _ content: () -> C) -> some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 6).fill(bg).overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            content().frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(tag).font(.system(size: 8)).padding(4).foregroundStyle(bg == .white ? .gray : .white.opacity(0.7))
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit).frame(maxWidth: 200)
    }

    private var youtubeBox: some View {
        GroupBox("YouTube (Kids)") {
            VStack(alignment: .leading, spacing: 6) {
                TextField("YouTube channel ID", text: $channel, prompt: Text("UC…")).textFieldStyle(.roundedBorder)
                Text("Lets Kids playlists pick from your recent live streams and use \"Live now\". Find it in YouTube Studio under Settings, Channel, Advanced settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(8)
        }
    }

    private var planBox: some View {
        GroupBox("Your plan") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(AppModule.allCases) { m in
                    let row = plan.first { $0.module == m.rawValue }
                    HStack(spacing: 6) {
                        Text(model.moduleName(m.rawValue)).fontWeight(.medium)
                        if let row {
                            let live = row.isLive(churchSuspended: false)
                            Text(live ? "Enabled" : "Not enabled").foregroundStyle(live ? .green : .red)
                            Text(row.summary).foregroundStyle(.secondary)
                        } else { Text("Not included").foregroundStyle(.secondary) }
                    }
                }
                Text("Billing and plan changes are on the website.").font(.caption).foregroundStyle(.secondary)
                Link("Open the website", destination: AppLinks.dashboard).font(.caption)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
    }

    // MARK: Actions

    private func load() async {
        guard let org = model.church?.id, let ops = model.ops else { return }
        do {
            let o = try await ops.loadOrganization(id: org)
            original = o; name = o.name; branding = o.branding; channel = o.branding.youtubeChannelId ?? ""
            plan = (try? await ops.loadPlan(organizationId: org)) ?? []
            loadError = nil
        } catch { loadError = Formatting.message(for: error) }
    }

    private func revert() {
        guard let o = original else { return }
        name = o.name; branding = o.branding; channel = o.branding.youtubeChannelId ?? ""; error = nil
    }

    private func save() {
        guard let org = model.church?.id else { return }
        var b = branding
        b.youtubeChannelId = channel
        if let p = BrandingSettings.problem(name: name, youtubeChannelId: channel) { error = p; return }
        saving = true; error = nil; saved = false
        Task {
            defer { saving = false }
            do {
                try await model.ops?.saveOrganization(id: org, name: name, branding: b)
                original = OrganizationSettings(id: org, name: name.trimmingCharacters(in: .whitespacesAndNewlines), slug: original?.slug ?? "", branding: b)
                branding = b; saved = true
                await model.reloadChurches()
            } catch { self.error = Formatting.message(for: error) }
        }
    }

    private func chooseLogo(dark: Bool) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.message = "Choose a logo image"
        guard panel.runModal() == .OK, let url = panel.url, let org = model.church?.id else { return }
        let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/png"
        uploading = true; error = nil
        let scope = scope
        Task {
            defer { uploading = false }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let publicURL = try await model.ops?.uploadBrandingLogo(organizationId: org, fileURL: url, contentType: type)
                branding.update(scope) { if dark { $0.logoDarkURL = publicURL } else { $0.logoURL = publicURL } }
            } catch { self.error = Formatting.message(for: error) }
        }
    }
}

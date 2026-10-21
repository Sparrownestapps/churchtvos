import SwiftUI
import ChurchTVCore

// Platform admin console (Keith only): churches table with search and sort, church detail (plans and grants, suspend, notes, people,
// screens, usage, activity) and the activity log. Mirrors dashboard/src/admin. Every call is refused by the server for anyone else.

private extension AdminOrg {
    var seenSort: Date { lastSeenAt ?? .distantPast }
    var ownerSort: String { ownerEmails.first?.lowercased() ?? "" }
    var nameSort: String { name.lowercased() }
    var statusSort: Int { status == .suspended ? 1 : 0 }
}

@MainActor
@Observable
final class AdminModel {
    var orgs: [AdminOrg] = []
    var modules: [ModuleDef] = []
    var loaded = false
    var error: String?

    func load(_ app: MenuModel) async {
        guard let admin = app.admin else { return }
        do {
            orgs = try await admin.adminListOrganizations()
            modules = (try? await app.ops?.listModules(availableOnly: false)) ?? []
            error = nil
        } catch { self.error = Formatting.message(for: error) }
        loaded = true
    }

    func moduleName(_ id: String) -> String { modules.first { $0.id == id }?.name ?? id.capitalized }
}

struct AdminSection: View {
    @Environment(MenuModel.self) private var app
    @State private var model = AdminModel()
    private enum Tab: String, CaseIterable { case churches = "Churches", activity = "Activity" }
    @State private var tab: Tab = CommandLine.arguments.contains("-admintab") && CommandLine.arguments.contains("activity") ? .activity : .churches
    @State private var openId: UUID?

    var body: some View {
        Group {
            if !app.isPlatformAdmin {
                ContentUnavailableView("Platform administrator only", systemImage: "lock", description: Text("This console is for the person who runs Church TV OS."))
            } else if let id = openId, let org = model.orgs.first(where: { $0.id == id }) {
                ChurchDetailView(org: org, model: model, onBack: { openId = nil }).id(id)
            } else {
                VStack(spacing: 0) {
                    Picker("Admin", selection: $tab) { ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden().frame(width: 240).padding(10)
                    Divider()
                    switch tab {
                    case .churches: ChurchesTable(model: model, onOpen: { openId = $0 })
                    case .activity: ActivityView(model: model)
                    }
                }
            }
        }
        .task { await model.load(app) }
        .onAppear { if let a = CommandLine.arguments.firstIndex(of: "-adminopen"), a + 1 < CommandLine.arguments.count { debugOpen(CommandLine.arguments[a + 1]) } }
    }

    private func debugOpen(_ slug: String) {
        Task {
            while !model.loaded { try? await Task.sleep(nanoseconds: 100_000_000) }
            openId = model.orgs.first { $0.slug.contains(slug) }?.id
        }
    }
}

// MARK: - Churches table

private struct ChurchesTable: View {
    @Environment(MenuModel.self) private var app
    let model: AdminModel
    let onOpen: (UUID) -> Void
    @State private var search = ""
    @State private var bucket: AdminLogic.Bucket = .all
    @State private var order = [KeyPathComparator(\AdminOrg.createdAt, order: .reverse)]
    @State private var selection: UUID?

    private var rows: [AdminOrg] {
        AdminLogic.rows(model.orgs, search: search, bucket: bucket, sort: .created, descending: true).sorted(using: order)
    }

    var body: some View {
        VStack(spacing: 0) {
            stats
            HStack {
                TextField("Search name, short name or owner email", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 360)
                Picker("Show", selection: $bucket) {
                    ForEach(AdminLogic.Bucket.allCases) { b in Text("\(b.title) (\(model.orgs.filter { AdminLogic.inBucket($0, b) }.count))").tag(b) }
                }.frame(maxWidth: 300)
                Spacer()
                Button { Task { await model.load(app) } } label: { Label("Reload", systemImage: "arrow.clockwise") }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            if let e = model.error { Text("Couldn't load churches: \(e)").foregroundStyle(.red).padding(.horizontal, 14) }
            Table(rows, selection: $selection, sortOrder: $order) {
                TableColumn("Church", value: \.nameSort) { o in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) { Text(o.name).fontWeight(.medium); if o.reviewedAt == nil { Badge(text: "New", tone: .warn) } }
                        Text(o.slug).font(.caption).foregroundStyle(.secondary)
                    }
                }.width(min: 170, ideal: 220)
                TableColumn("Owner", value: \.ownerSort) { o in Text(o.ownerEmails.isEmpty ? "none" : o.ownerEmails.joined(separator: ", ")).lineLimit(2) }.width(min: 150, ideal: 200)
                TableColumn("Signed up", value: \.createdAt) { o in
                    VStack(alignment: .leading, spacing: 1) { Text(AdminLogic.relDays(o.createdAt)); Text(o.createdAt.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary) }
                }.width(min: 90, ideal: 110)
                TableColumn("Plan") { o in PlanChips(org: o, moduleName: model.moduleName) }.width(min: 220, ideal: 300)
                TableColumn("Last TV seen", value: \.seenSort) { o in Text(o.lastSeenAt == nil ? "never" : Formatting.ago(o.lastSeenAt)) }.width(min: 80, ideal: 100)
                TableColumn("Members", value: \.memberCount) { o in Text("\(o.memberCount)") }.width(60)
                TableColumn("Media", value: \.storageBytes) { o in Text(o.mediaCount == 0 ? "-" : "\(Formatting.bytes(o.storageBytes)) (\(o.mediaCount))") }.width(min: 90, ideal: 120)
                TableColumn("Status", value: \.statusSort) { o in Badge(text: o.status == .suspended ? "Suspended" : "Active", tone: o.status == .suspended ? .bad : .ok) }.width(80)
            }
            .contextMenu(forSelectionType: UUID.self) { _ in } primaryAction: { ids in if let id = ids.first { onOpen(id) } }
            .overlay { if !model.loaded { ProgressView() } else if rows.isEmpty { Text("No churches match.").foregroundStyle(.secondary) } }
            Divider()
            HStack { Text("Double-click a church to open it.").font(.caption).foregroundStyle(.secondary); Spacer() }.padding(.horizontal, 14).padding(6)
        }
    }

    private var stats: some View {
        let s = AdminLogic.stats(model.orgs)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Stat(label: "Churches", value: "\(s.total)")
                Stat(label: "New, not reviewed", value: "\(s.fresh)", tone: s.fresh > 0 ? .warn : nil) { bucket = .new }
                Stat(label: "Trials ending in 7 days", value: "\(s.ending)", tone: s.ending > 0 ? .warn : nil)
                Stat(label: "Expired or no live plan", value: "\(s.expired)", tone: s.expired > 0 ? .bad : nil) { bucket = .expired }
                Stat(label: "Suspended", value: "\(s.suspended)") { bucket = .suspended }
                Stat(label: "TVs paired", value: "\(s.tvs)")
                Stat(label: "Storage used", value: s.bytes == 0 ? "0 KB" : Formatting.bytes(s.bytes))
            }.padding(.horizontal, 14).padding(.vertical, 10)
        }
    }
}

private struct Stat: View {
    let label: String
    let value: String
    var tone: AdminLogic.Tone?
    var action: (() -> Void)?

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.weight(.semibold).monospacedDigit()).foregroundStyle(tone.map(toneColor) ?? Color.primary)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 8).frame(minWidth: 120, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
        if let action { Button(action: action) { content }.buttonStyle(.plain) } else { content }
    }
}

func toneColor(_ t: AdminLogic.Tone) -> Color { switch t { case .ok: return .green; case .warn: return .orange; case .bad: return .red; case .off: return .secondary } }

private struct Badge: View {
    let text: String
    let tone: AdminLogic.Tone
    var body: some View {
        Text(text).font(.caption2.weight(.semibold)).padding(.horizontal, 7).padding(.vertical, 2)
            .background(toneColor(tone).opacity(0.16), in: Capsule()).foregroundStyle(toneColor(tone))
    }
}

private struct PlanChips: View {
    let org: AdminOrg
    let moduleName: (String) -> String
    var body: some View {
        if org.entitlements.isEmpty { Badge(text: "No plan", tone: .bad) }
        else {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) { ForEach(org.entitlements, id: \.module) { e in let c = AdminLogic.planChip(e, org.status); Badge(text: "\(moduleName(e.module)): \(c.text)", tone: c.tone) } }
                Text("\(org.screenCount)/\(AdminLogic.tvLimit(org)) TVs").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Church detail

private struct ChurchDetailView: View {
    @Environment(MenuModel.self) private var app
    let org: AdminOrg
    let model: AdminModel
    let onBack: () -> Void
    @State private var busy = false
    @State private var error: String?
    @State private var confirm: Confirmation?
    @State private var reason = ""
    @State private var notes: String
    @State private var notesSaved = false

    struct Confirmation: Identifiable { let id = UUID(); let title: String; let message: String; let button: String; let destructive: Bool; let action: () async -> Void }

    init(org: AdminOrg, model: AdminModel, onBack: @escaping () -> Void) {
        self.org = org; self.model = model; self.onBack = onBack; _notes = State(initialValue: org.adminNotes ?? "")
    }

    private var suspended: Bool { org.status == .suspended }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let error { Text(error).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading) }
                PlanBox(org: org, model: model, run: run, ask: { confirm = $0 })
                experimental
                suspendBox
                PeopleBox(org: org, model: model, ask: { confirm = $0 })
                ScreensBox(org: org)
                usage
                notesBox
                ActivityBox(org: org, model: model)
                GroupBox("Danger zone") {
                    HStack {
                        Text("Deleting a church and its stored files is not built into the Mac app. Use the website's Admin console, where the confirmation by short name lives.").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Link("Open the website", destination: AppLinks.dashboard)
                    }.padding(6)
                }
            }
            .padding(20).frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity)
        }
        .confirmationDialog(confirm?.title ?? "", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), titleVisibility: .visible, presenting: confirm) { c in
            Button(c.button, role: c.destructive ? .destructive : nil) { Task { await c.action() } }
            Button("Cancel", role: .cancel) {}
        } message: { c in Text(c.message) }
    }

    /// Runs an admin write, shows its error, then reloads the church list.
    func run(_ work: @escaping () async throws -> Void) async {
        busy = true; error = nil
        defer { busy = false }
        do { try await work(); await model.load(app) } catch { self.error = Formatting.message(for: error) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { onBack() } label: { Label("All churches", systemImage: "chevron.left") }.buttonStyle(.link)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(org.name).font(.title.weight(.semibold))
                if org.reviewedAt == nil { Badge(text: "New", tone: .warn) }
                Badge(text: suspended ? "Suspended" : "Active", tone: suspended ? .bad : .ok)
                Spacer()
                if org.reviewedAt == nil { Button("Mark reviewed") { Task { await run { try await app.admin?.adminUpdateOrganization(org.id, change: AdminOrgChange(reviewed: true)) } } }.buttonStyle(.borderedProminent).disabled(busy) }
            }
            Text("\(org.slug) · signed up \(AdminLogic.relDays(org.createdAt)) (\(org.createdAt.formatted(date: .abbreviated, time: .omitted))) · \(org.ownerEmails.joined(separator: ", ").isEmpty ? "no owner yet" : org.ownerEmails.joined(separator: ", "))").foregroundStyle(.secondary)
            if suspended, let r = org.suspendedReason, !r.isEmpty { Text("Suspended: \(r)").foregroundStyle(.red) }
        }
    }

    private var experimental: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("Experimental features").font(.headline); Badge(text: org.ndiEnabled ? "NDI on" : "All off", tone: org.ndiEnabled ? .bad : .ok) }
                Text("Do not enable for customers. The NDI SDK licence for Android is unconfirmed: NDI's licence says Android and fixed-purpose devices need a separate commercial agreement with NDI. Use only for churches you are testing with.")
                    .font(.callout).foregroundStyle(.red)
                Toggle("NDI source (experimental) in Kids playlists and Slides decks", isOn: Binding(get: { org.ndiEnabled }, set: { on in
                    confirm = Confirmation(title: on ? "Switch ON experimental NDI sources for \(org.name)?" : "Switch OFF experimental NDI sources for \(org.name)?",
                                           message: on ? "The NDI SDK licence for Android is unconfirmed. Do not enable this for customers. Only for churches you are testing with, on TVs running the special NDI build."
                                                       : "Existing NDI items stay saved but stop playing on their TVs, and the editors hide the option.",
                                           button: on ? "Switch on" : "Switch off", destructive: on) { await run { try await app.admin?.adminUpdateOrganization(org.id, change: AdminOrgChange(ndi: on)) } }
                })).disabled(busy)
                Text("Who switched it and when is recorded in the activity log below.").font(.caption).foregroundStyle(.secondary)
            }.padding(6)
        }
    }

    private var suspendBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(suspended ? "Reactivate this church" : "Suspend this church").font(.headline)
                Text("Suspending means TVs stop showing content and members cannot use modules until you reactivate. Their data is kept. Every change is recorded in the activity log.").font(.callout).foregroundStyle(.secondary)
                if suspended {
                    Button("Reactivate") { confirm = Confirmation(title: "Reactivate \(org.name)?", message: "", button: "Reactivate", destructive: false) { await run { try await app.admin?.adminUpdateOrganization(org.id, change: AdminOrgChange(status: .active)) } } }.disabled(busy)
                } else {
                    TextField("Reason (only you see this)", text: $reason, prompt: Text("e.g. Unpaid invoice, abuse report"), axis: .vertical).lineLimit(2...3).textFieldStyle(.roundedBorder)
                    Button("Suspend…", role: .destructive) {
                        let r = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                        confirm = Confirmation(title: "Suspend \(org.name)?", message: "Their TVs will stop showing content.", button: "Suspend", destructive: true) { await run { try await app.admin?.adminUpdateOrganization(org.id, change: AdminOrgChange(status: .suspended, reason: r)) }; reason = "" }
                    }.disabled(busy)
                }
            }.padding(6)
        }
    }

    private var usage: some View {
        let limit = AdminLogic.tvLimit(org)
        return GroupBox("Usage") {
            VStack(alignment: .leading, spacing: 8) {
                Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 6) {
                    GridRow { usageCell("Media", "\(org.mediaCount) files, \(org.storageBytes == 0 ? "0 KB" : Formatting.bytes(org.storageBytes))"); usageCell("Songs", "\(org.songCount)"); usageCell("Decks", "\(org.deckCount)") }
                    GridRow { usageCell("Playlists", "\(org.playlistCount)"); usageCell("TVs", "\(org.screenCount) of \(limit) allowed", bad: org.screenCount > limit); usageCell("Members", "\(org.memberCount)") }
                }
                if org.screenCount > limit { Text("More TVs are paired than the current limit allows. Existing TVs keep working; new pairing is refused.").foregroundStyle(.red).font(.callout) }
            }.padding(6)
        }
    }

    private func usageCell(_ k: String, _ v: String, bad: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) { Text(k).font(.caption).foregroundStyle(.secondary); Text(v).fontWeight(.medium).foregroundStyle(bad ? Color.red : Color.primary) }
    }

    private var notesBox: some View {
        GroupBox("Internal notes") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Only platform administrators can see these. They are never shown to the church.").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $notes).frame(minHeight: 90).overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                HStack {
                    Button("Save notes") { Task { await run { try await app.admin?.adminUpdateOrganization(org.id, change: AdminOrgChange(notes: notes)); notesSaved = true } } }.buttonStyle(.borderedProminent).disabled(busy)
                    if notesSaved { Text("Saved").foregroundStyle(.green) }
                }
            }.padding(6)
        }
    }
}

// MARK: Plan and grants

private struct PlanBox: View {
    @Environment(MenuModel.self) private var app
    let org: AdminOrg
    let model: AdminModel
    let run: (@escaping () async throws -> Void) async -> Void
    let ask: (ChurchDetailView.Confirmation) -> Void
    @State private var onlyTicked = false
    @State private var ticked: Set<String> = []

    private var ids: [String] {
        let known = model.modules.map(\.id)
        return known + org.entitlements.map(\.module).filter { !known.contains($0) }
    }

    var body: some View {
        GroupBox("Plan and permissions") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Text("Quick presets for").fontWeight(.medium)
                    Picker("", selection: $onlyTicked) { Text("All modules this church has").tag(false); Text("Only ticked modules").tag(true) }.pickerStyle(.radioGroup).horizontalRadioGroupLayout().labelsHidden()
                }
                HStack { ForEach(AdminLogic.Preset.allCases) { p in Button(p.title) { preset(p) } } }.controlSize(.small)
                Divider()
                ForEach(ids, id: \.self) { id in
                    let cur = org.entitlements.first { $0.module == id }
                    EntitlementEditor(org: org, module: id, name: model.moduleName(id), released: model.modules.first { $0.id == id }?.available ?? false, current: cur,
                                      ticked: ticked.contains(id), onTick: { if $0 { ticked.insert(id) } else { ticked.remove(id) } }, run: run, ask: ask)
                        .id("\(id)-\(cur.map { "\($0.status)\($0.tvLimit)\($0.plan)\($0.currentPeriodEnd?.timeIntervalSince1970 ?? 0)\($0.graceEndsAt?.timeIntervalSince1970 ?? 0)" } ?? "none")")
                    Divider()
                }
                Text("What the TV limit means: the number of TVs this church may have paired at once. When a church already has that many paired and tries to pair another, the pairing is refused with a plan-limit message. If several modules are live, the largest limit applies. Lowering the limit does not unpair TVs that are already paired.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("When is a module live? Active plans are live. A trial is live until its end date (live indefinitely if there is no date). A past-due plan is live until its grace date. Nothing is live while the church is suspended.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(6)
        }
    }

    private func preset(_ p: AdminLogic.Preset) {
        let targets = onlyTicked ? Array(ticked) : org.entitlements.map(\.module)
        guard !targets.isEmpty else { ask(.init(title: "No modules chosen", message: onlyTicked ? "Tick at least one module first." : "This church has no modules yet. Tick modules and choose \"Only ticked modules\".", button: "OK", destructive: false) {}); return }
        let rows = targets.compactMap { m in AdminLogic.applyPreset(p, orgId: org.id, module: m, current: org.entitlements.first { $0.module == m }) }
        guard !rows.isEmpty else { ask(.init(title: "\"\(p.title)\" doesn't apply", message: "To \(targets.map(model.moduleName).joined(separator: ", ")).", button: "OK", destructive: false) {}); return }
        ask(.init(title: p.title, message: "Apply to: \(rows.map { model.moduleName($0.module) }.joined(separator: ", "))?", button: "Apply", destructive: false) {
            await run { try await app.admin?.adminUpsertEntitlements(rows) }
        })
    }
}

private struct EntitlementEditor: View {
    @Environment(MenuModel.self) private var app
    let org: AdminOrg
    let module: String
    let name: String
    let released: Bool
    let current: AdminEnt?
    let ticked: Bool
    let onTick: (Bool) -> Void
    let run: (@escaping () async throws -> Void) async -> Void
    let ask: (ChurchDetailView.Confirmation) -> Void

    @State private var status: String
    @State private var limit: Int
    @State private var plan: String
    @State private var hasEnd: Bool
    @State private var end: Date
    @State private var hasGrace: Bool
    @State private var grace: Date

    init(org: AdminOrg, module: String, name: String, released: Bool, current: AdminEnt?, ticked: Bool, onTick: @escaping (Bool) -> Void,
         run: @escaping (@escaping () async throws -> Void) async -> Void, ask: @escaping (ChurchDetailView.Confirmation) -> Void) {
        self.org = org; self.module = module; self.name = name; self.released = released; self.current = current; self.ticked = ticked; self.onTick = onTick; self.run = run; self.ask = ask
        _status = State(initialValue: current?.status ?? "active"); _limit = State(initialValue: current?.tvLimit ?? 2); _plan = State(initialValue: current?.plan ?? "standard")
        _hasEnd = State(initialValue: current?.currentPeriodEnd != nil); _end = State(initialValue: current?.currentPeriodEnd ?? Date().addingTimeInterval(30 * 86400))
        _hasGrace = State(initialValue: current?.graceEndsAt != nil); _grace = State(initialValue: current?.graceEndsAt ?? Date().addingTimeInterval(7 * 86400))
    }

    private var row: AdminEntitlementRow {
        AdminEntitlementRow(organizationId: org.id, module: module, status: status, tvLimit: limit, plan: plan,
                            currentPeriodEnd: hasEnd ? AdminLogic.endOfDay(end) : nil, graceEndsAt: hasGrace ? AdminLogic.endOfDay(grace) : nil)
    }
    private var wouldBeLive: Bool { AdminLogic.isLive(status: status, currentPeriodEnd: row.currentPeriodEnd, graceEndsAt: row.graceEndsAt, orgStatus: org.status) }
    private var liveNow: Bool { current.map { AdminLogic.isLive($0, org.status) } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(isOn: Binding(get: { ticked }, set: onTick)) { Text(name).fontWeight(.semibold) }.toggleStyle(.checkbox)
                if !released { Badge(text: "not released", tone: .off) }
                Spacer()
                if let current {
                    let left = current.status == "trialing" ? AdminLogic.daysLeft(current.currentPeriodEnd) : nil
                    Badge(text: (liveNow ? "LIVE now" : (org.status == .suspended ? "Not live (suspended)" : "NOT live")) + (left != nil && liveNow ? " · \(max(left!, 0))d left" : ""), tone: liveNow ? .ok : .bad)
                } else { Badge(text: "Not included", tone: .off) }
            }
            HStack(alignment: .bottom, spacing: 14) {
                Picker("Status", selection: $status) { ForEach(AdminLogic.statuses, id: \.self) { Text($0).tag($0) } }.frame(width: 150)
                Stepper(value: $limit, in: 0...9999) { Text("TV limit \(limit)") }.frame(width: 140)
                TextField("Plan name", text: $plan).frame(width: 120)
                VStack(alignment: .leading, spacing: 2) { Toggle("Trial / period ends", isOn: $hasEnd); if hasEnd { DatePicker("", selection: $end, displayedComponents: .date).labelsHidden() } }
                VStack(alignment: .leading, spacing: 2) { Toggle("Grace ends", isOn: $hasGrace); if hasGrace { DatePicker("", selection: $grace, displayedComponents: .date).labelsHidden() } }
                Spacer()
                Button(current == nil ? "Add" : "Save") { Task { await run { try await app.admin?.adminUpsertEntitlements([row]) } } }.buttonStyle(.borderedProminent)
                if current != nil {
                    Button("Remove", role: .destructive) {
                        ask(.init(title: "Remove \(name) from this church?", message: "It will lose access to the module.", button: "Remove", destructive: true) {
                            await run { try await app.admin?.adminDeleteEntitlement(organizationId: org.id, module: module) }
                        })
                    }
                }
            }
            Text((current.map { "Saved: \($0.status), \($0.plan), \($0.tvLimit) TV\($0.tvLimit == 1 ? "" : "s")\($0.currentPeriodEnd.map { ", ends \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "")\($0.graceEndsAt.map { ", grace to \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""). " } ?? "") + "With these values it would be \(wouldBeLive ? "live" : "not live").")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: People, screens, activity of one church

private struct PeopleBox: View {
    @Environment(MenuModel.self) private var app
    let org: AdminOrg
    let model: AdminModel
    let ask: (ChurchDetailView.Confirmation) -> Void
    @State private var people: [Member] = []
    @State private var email = ""
    @State private var role: Role = .owner
    @State private var error: String?

    var body: some View {
        GroupBox("People") {
            VStack(alignment: .leading, spacing: 8) {
                if let error { Text(error).foregroundStyle(.red) }
                ForEach(people) { m in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.email).fontWeight(.medium)
                            Text("\(m.role.displayName) · \(PeopleRules.hasEverything(m.role) ? "all modules" : (m.modules.isEmpty ? "no modules" : m.modules.map(model.moduleName).joined(separator: ", "))) · \(m.userId != nil ? "has signed in" : "not signed in yet")").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Remove", role: .destructive) {
                            ask(.init(title: "Remove \(m.email) from \(org.name)?", message: "", button: "Remove", destructive: true) {
                                do { try await app.admin?.adminRemoveMember(id: m.id, organizationId: org.id); await load() } catch { self.error = Formatting.message(for: error) }
                            })
                        }.buttonStyle(.link)
                    }
                }
                if people.isEmpty { Text("Nobody has access yet.").foregroundStyle(.secondary) }
                Divider()
                HStack {
                    TextField("Add a person by email", text: $email, prompt: Text("name@church.org")).textFieldStyle(.roundedBorder)
                    Picker("Role", selection: $role) { ForEach(Role.allCases, id: \.self) { Text($0.displayName).tag($0) } }.frame(width: 160)
                    Button("Add") { add() }.disabled(email.isEmpty)
                }
                Text("No email is sent. They sign in or create an account with this same address and the church appears. New people get every released module and all sites. The last owner cannot be removed.").font(.caption).foregroundStyle(.secondary)
            }.padding(6)
        }
        .task { await load() }
    }

    private func load() async {
        do { people = try await app.admin?.adminListMembers(organizationId: org.id) ?? []; error = nil } catch { self.error = Formatting.message(for: error) }
    }

    private func add() {
        Task {
            do {
                try await app.admin?.adminInviteMember(organizationId: org.id, email: email, role: role, moduleIds: model.modules.filter(\.available).map(\.id))
                email = ""; await load()
            } catch { self.error = Formatting.message(for: error) }
        }
    }
}

private struct ScreensBox: View {
    @Environment(MenuModel.self) private var app
    let org: AdminOrg
    @State private var screens: [AdminScreenRow] = []
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        GroupBox("Screens (\(loaded ? screens.count : org.screenCount))") {
            VStack(alignment: .leading, spacing: 6) {
                if let error { Text(error).foregroundStyle(.red) }
                if loaded && screens.isEmpty { Text("No TVs paired.").foregroundStyle(.secondary) }
                ForEach(screens) { s in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.name ?? "Unnamed TV").fontWeight(.medium)
                            Text("\(s.locationName ?? "No location") · \(ScreenOrientation(rawValue: s.orientation ?? "")?.displayName ?? "Landscape") · app \(s.appVersion ?? "unknown")\(s.model.map { " · \($0)" } ?? "")").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Badge(text: "\(s.isOnline() ? "Online" : "Offline") · seen \(Formatting.ago(s.lastSeenAt))", tone: s.isOnline() ? .ok : .off)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
        }
        .task {
            do { screens = try await app.admin?.adminListScreens(organizationId: org.id) ?? [] } catch { self.error = Formatting.message(for: error) }
            loaded = true
        }
    }
}

private struct ActivityBox: View {
    @Environment(MenuModel.self) private var app
    let org: AdminOrg
    let model: AdminModel
    @State private var entries: [AuditEntry] = []

    var body: some View {
        GroupBox("Activity") {
            AuditList(entries: entries, names: [org.id: org.name], moduleName: model.moduleName, showChurch: false).padding(6)
        }
        .task { entries = (try? await app.admin?.adminListAudit(organizationId: org.id, action: nil, page: 0, pageSize: 50)) ?? [] }
    }
}

private struct AuditList: View {
    let entries: [AuditEntry]
    let names: [UUID: String]
    let moduleName: (String) -> String
    var showChurch = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if entries.isEmpty { Text("Nothing recorded yet.").foregroundStyle(.secondary) }
            ForEach(entries) { a in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(a.at.formatted(date: .abbreviated, time: .shortened)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(AdminLogic.describeAudit(a, moduleName: moduleName))
                        Text([showChurch ? a.organizationId.flatMap { names[$0] } : nil, a.actorEmail].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ActivityView: View {
    @Environment(MenuModel.self) private var app
    let model: AdminModel
    private let pageSize = 50
    @State private var church: UUID?
    @State private var action: String?
    @State private var page = 0
    @State private var entries: [AuditEntry] = []
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Church", selection: $church) { Text("All churches").tag(UUID?.none); ForEach(model.orgs) { Text($0.name).tag(Optional($0.id)) } }.frame(maxWidth: 280)
                Picker("Action", selection: $action) { Text("All actions").tag(String?.none); ForEach(AdminLogic.auditActions, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag(Optional($0)) } }.frame(maxWidth: 240)
                Spacer()
            }.padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading) {
                    if let error { Text(error).foregroundStyle(.red) }
                    AuditList(entries: Array(entries.prefix(pageSize)), names: Dictionary(model.orgs.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a }), moduleName: model.moduleName)
                }.padding(14)
            }
            Divider()
            HStack {
                Button("Newer") { page -= 1 }.disabled(page == 0)
                Button("Older") { page += 1 }.disabled(entries.count <= pageSize)
                Text("Page \(page + 1)").foregroundStyle(.secondary)
                Spacer()
            }.padding(10)
        }
        .task(id: "\(church?.uuidString ?? "")-\(action ?? "")-\(page)") {
            do { entries = try await app.admin?.adminListAudit(organizationId: church, action: action, page: page, pageSize: pageSize) ?? []; error = nil } catch { self.error = Formatting.message(for: error) }
        }
        .onChange(of: church) { _, _ in page = 0 }
        .onChange(of: action) { _, _ in page = 0 }
    }
}

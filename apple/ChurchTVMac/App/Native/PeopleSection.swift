import SwiftUI
import ChurchTVCore

/// People: invite, change role, modules and sites, remove. Mirrors the website's People page (memberships table). Owners and admins only.
struct PeopleSection: View {
    @Environment(MenuModel.self) private var model
    @State private var members: [Member] = []
    @State private var sites: [Site] = []
    @State private var loaded = false
    @State private var loadError: String?
    @State private var selection: UUID?
    @State private var showInvite = false
    @State private var toRemove: Member?
    @State private var actionError: String?

    private var availableModules: [ModuleDef] {
        model.moduleRegistry.isEmpty ? AppModule.allCases.map { ModuleDef(id: $0.rawValue, name: $0.displayName) } : model.moduleRegistry
    }
    private var moduleNames: [String: String] { Dictionary(uniqueKeysWithValues: availableModules.map { ($0.id, $0.name) }) }
    private var allowed: Bool { model.church.map { PeopleRules.canManage($0.role) } ?? false }

    var body: some View {
        Group {
            if !allowed {
                ContentUnavailableView("Owners and admins only", systemImage: "lock", description: Text("Ask a church admin to change who has access."))
            } else {
                HSplitView {
                    list.frame(minWidth: 320, idealWidth: 380)
                    detail.frame(minWidth: 380)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showInvite = true } label: { Label("Invite", systemImage: "person.badge.plus") }.disabled(!allowed)
            }
        }
        .sheet(isPresented: $showInvite) {
            InviteForm(modules: availableModules, sites: sites, initial: AccessDraft.blank(modules: availableModules.map(\.id))) { draft in
                guard let org = model.church?.id else { return }
                try await model.ops?.inviteMember(organizationId: org, draft: draft)
                await load()
            }
        }
        .confirmationDialog("Remove \(toRemove?.email ?? "")'s access?", isPresented: Binding(get: { toRemove != nil }, set: { if !$0 { toRemove = nil } }), titleVisibility: .visible) {
            Button("Remove", role: .destructive) { if let m = toRemove { remove(m) } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Couldn't finish", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(actionError ?? "") }
        .task { await load() }
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(members) { m in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(m.email).font(.body.weight(.medium)).lineLimit(1)
                        if m.userId != nil && m.userId == model.user?.id { Text("(you)").foregroundStyle(.secondary) }
                    }
                    Text(PeopleRules.summary(m, moduleNames: moduleNames, sites: sites)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                .padding(.vertical, 2).tag(m.id)
            }
        }
        .listStyle(.inset)
        .overlay {
            if !loaded { ProgressView() }
            else if let e = loadError { Text(e).foregroundStyle(.red).padding() }
        }
    }

    @ViewBuilder private var detail: some View {
        if let m = members.first(where: { $0.id == selection }) {
            PersonDetail(member: m, modules: availableModules, sites: sites,
                         canRemove: PeopleRules.canRemove(m, currentUserId: model.user?.id),
                         onSave: { draft in
                             try await model.ops?.updateMember(id: m.id, draft: draft)
                             await load()
                         },
                         onRemove: { toRemove = m })
                .id(m.id)
        } else {
            ContentUnavailableView(members.count <= 1 && loaded ? "It is just you so far" : "Choose a person", systemImage: "person.2",
                                   description: Text(members.count <= 1 && loaded ? "Invite volunteers and staff, and choose which applications and sites they can use. " + PeopleRules.inviteNote : PeopleRules.inviteNote))
        }
    }

    private func load() async {
        guard let org = model.church?.id, let ops = model.ops else { return }
        do {
            members = try await ops.listMembers(organizationId: org)
            sites = (try? await model.service.listSites(organizationId: org)) ?? []
            loadError = nil
            if CommandLine.arguments.contains("-personpick"), selection == nil { selection = members.first(where: { $0.role == .editor })?.id }
        } catch { loadError = Formatting.message(for: error) }
        loaded = true
    }

    private func remove(_ m: Member) {
        Task {
            do { try await model.ops?.removeMember(id: m.id, organizationId: m.organizationId); if selection == m.id { selection = nil }; await load() }
            catch { actionError = Formatting.message(for: error) }
        }
    }
}

private struct PersonDetail: View {
    let member: Member
    let modules: [ModuleDef]
    let sites: [Site]
    let canRemove: Bool
    let onSave: (AccessDraft) async throws -> Void
    let onRemove: () -> Void

    @State private var draft: AccessDraft
    @State private var error: String?
    @State private var saving = false
    @State private var saved = false

    init(member: Member, modules: [ModuleDef], sites: [Site], canRemove: Bool, onSave: @escaping (AccessDraft) async throws -> Void, onRemove: @escaping () -> Void) {
        self.member = member; self.modules = modules; self.sites = sites; self.canRemove = canRemove; self.onSave = onSave; self.onRemove = onRemove
        _draft = State(initialValue: AccessDraft(member))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(member.email).font(.title2.weight(.semibold))
                    Text(member.userId != nil ? "Active" : "Invited, not signed up yet").foregroundStyle(.secondary)
                }
                AccessFields(draft: $draft, modules: modules, sites: sites)
                if let error { Text(error).foregroundStyle(.red) }
                HStack {
                    Button("Save") { save() }.keyboardShortcut("s").buttonStyle(.borderedProminent).disabled(draft == AccessDraft(member) || saving)
                    if saved && draft == AccessDraft(member) { Label("Saved", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                    Spacer()
                    if canRemove { Button("Remove access…", role: .destructive, action: onRemove) }
                }
            }
            .padding(20).frame(maxWidth: 560, alignment: .leading)
        }
    }

    private func save() {
        saving = true; error = nil
        Task {
            defer { saving = false }
            do { try await onSave(draft); saved = true } catch { self.error = Formatting.message(for: error) }
        }
    }
}

/// Role, modules and sites (the website's AccessFields).
struct AccessFields: View {
    @Binding var draft: AccessDraft
    let modules: [ModuleDef]
    let sites: [Site]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Role", selection: $draft.role) {
                ForEach(Role.allCases, id: \.self) { Text("\($0.displayName): \(PeopleRules.roleHelp($0))").tag($0) }
            }
            if PeopleRules.hasEverything(draft.role) {
                Text("Owners and admins always have every module and every site.").foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Modules").font(.subheadline.weight(.medium))
                    HStack(spacing: 16) {
                        ForEach(modules) { m in
                            Toggle(m.name, isOn: Binding(get: { draft.modules.contains(m.id) }, set: { _ in draft.toggleModule(m.id) }))
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sites").font(.subheadline.weight(.medium))
                    Toggle("All sites", isOn: Binding(get: { draft.siteIds == nil }, set: { draft.setAllSites($0) }))
                    if draft.siteIds != nil {
                        ForEach(sites) { s in
                            Toggle(s.name, isOn: Binding(get: { draft.siteIds?.contains(s.id) ?? false }, set: { _ in draft.toggleSite(s.id) })).padding(.leading, 18)
                        }
                        if sites.isEmpty { Text("This church has no sites yet.").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }
    }
}

struct InviteForm: View {
    @Environment(\.dismiss) private var dismiss
    let modules: [ModuleDef]
    let sites: [Site]
    @State var initial: AccessDraft
    let onSubmit: (AccessDraft) async throws -> Void
    @State private var error: String?
    @State private var busy = false

    init(modules: [ModuleDef], sites: [Site], initial: AccessDraft, onSubmit: @escaping (AccessDraft) async throws -> Void) {
        self.modules = modules; self.sites = sites; _initial = State(initialValue: initial); self.onSubmit = onSubmit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Invite someone").font(.title2.weight(.semibold))
            TextField("Email", text: $initial.email, prompt: Text("name@church.org")).textFieldStyle(.roundedBorder)
            AccessFields(draft: $initial, modules: modules, sites: sites)
            Text(PeopleRules.inviteNote).font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Give access") { submit() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(busy)
            }
        }
        .padding(22).frame(width: 480)
    }

    private func submit() {
        if let p = PeopleRules.problem(initial, isInvite: true) { error = p; return }
        busy = true; error = nil
        Task {
            defer { busy = false }
            do { try await onSubmit(initial); dismiss() } catch { self.error = Formatting.message(for: error) }
        }
    }
}

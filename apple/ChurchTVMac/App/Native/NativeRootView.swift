import SwiftUI
import AppKit
import ChurchTVCore

/// The main window: sign-in, or the sidebar plus the section's detail.
struct NativeRootView: View {
    @Environment(MenuModel.self) private var model

    var body: some View {
        Group {
            if model.launching { ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if model.isSignedIn { Shell() }
            else { NativeSignInView() }
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(WindowFrameSaver(name: "ChurchTVNativeWindow"))
    }
}

private struct Shell: View {
    @Environment(MenuModel.self) private var model
    @State private var nav = NavState.shared

    private var visible: [AppSection] { AppSection.visible(church: model.church, isPlatformAdmin: model.isPlatformAdmin) }

    var body: some View {
        NavigationSplitView(columnVisibility: $nav.sidebarVisible) {
            Sidebar(visible: visible)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            SectionDetail(section: nav.section)
                .id("\(model.church?.id.uuidString ?? "none")-\(nav.section.rawValue)")
                .navigationTitle(nav.section.title)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if model.useDemo { Text("DEMO").font(.caption2.bold()).padding(.horizontal, 7).padding(.vertical, 3).background(.orange.opacity(0.2), in: Capsule()).foregroundStyle(.orange) }
            }
            ToolbarItem(placement: .automatic) {
                Button { Task { await model.refreshNow() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }.help("Refresh TV status (⌘R)")
            }
        }
        .onChange(of: visible) { _, list in if !list.contains(nav.section), let first = list.first { nav.section = first } }
        .onAppear { if !visible.contains(nav.section), let first = visible.first { nav.section = first } }
    }
}

private struct Sidebar: View {
    @Environment(MenuModel.self) private var model
    @State private var nav = NavState.shared
    let visible: [AppSection]

    var body: some View {
        List(selection: Binding(get: { nav.section }, set: { if let s = $0 { nav.section = s } })) {
            ForEach(AppSection.Group.allCases, id: \.self) { group in
                let items = visible.filter { $0.group == group }
                if !items.isEmpty {
                    Section(group.rawValue) {
                        ForEach(items) { s in
                            Label(s.title, systemImage: s.symbol)
                                .badge(s == .screens && model.offlineCount > 0 ? Text("\(model.offlineCount)") : nil)
                                .tag(s)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) { ChurchSwitcher().padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 4) }
        .safeAreaInset(edge: .bottom, spacing: 0) { AccountFooter() }
    }
}

/// Church picker: the organization switcher.
private struct ChurchSwitcher: View {
    @Environment(MenuModel.self) private var model

    var body: some View {
        Menu {
            ForEach(model.churches) { c in
                Button { Task { await model.choose(c) } } label: {
                    if c.id == model.church?.id { Label(c.organization.name, systemImage: "checkmark") } else { Text(c.organization.name) }
                }
            }
            if model.churches.isEmpty { Text("No churches") }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "building.2.fill").foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.church?.organization.name ?? (model.isPlatformAdmin ? "Platform admin" : "No church")).font(.headline).lineLimit(1)
                    Text(model.isPlatformAdmin && model.church == nil ? "No church membership" : model.roleText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if model.churches.count > 1 { Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary) }
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
        .disabled(model.churches.count < 2)
        .help(model.churches.count > 1 ? "Switch church" : "Your church")
    }
}

private struct AccountFooter: View {
    @Environment(MenuModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle").foregroundStyle(.secondary)
                Text(model.useDemo ? "Demo (no account)" : (model.user?.email ?? "")).font(.caption).lineLimit(1).truncationMode(.middle)
                Spacer()
                Menu {
                    Button("Preferences…") { openSettings() }
                    Button(model.useDemo ? "Leave demo" : "Sign out", role: .destructive) { Task { await model.signOut() } }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .background(.bar)
    }
}

/// The detail of one section.
struct SectionDetail: View {
    @Environment(MenuModel.self) private var model
    let section: AppSection

    var body: some View {
        if section != .admin, model.church == nil {
            ContentUnavailableView("No church selected", systemImage: "building.2",
                                   description: Text(model.loadError ?? "Your account is not part of a church yet. Ask a church admin to invite you, or create one on the website."))
        } else if !section.isVisible(church: model.church, isPlatformAdmin: model.isPlatformAdmin) {
            ContentUnavailableView("Not available", systemImage: "lock", description: Text("Your role or your church's plan does not include this."))
        } else {
            switch section {
            case .screens: ScreensSection()
            case .remote: RemoteSection()
            case .calendar: CalendarSection()
            case .media: MediaSection()
            case .songs: SongsSection()
            case .kids, .signage, .slides, .themes: CreateSectionView(section: section)
            case .people: PeopleSection()
            case .settings: ChurchSettingsSection()
            case .sites: WebFallbackSection(section: section)
            case .admin: AdminSection()
            }
        }
    }
}

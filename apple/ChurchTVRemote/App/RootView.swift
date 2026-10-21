import SwiftUI
import ChurchTVCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch model.phase {
            case .launching:
                ProgressView("Starting…").controlSize(.large)
            case .signedOut:
                SignInView()
            case .chooseChurch:
                ChurchPickerView()
            case .ready:
                #if DEBUG
                if model.showKitGallery { KitGalleryView() } else { MainView() }
                #else
                MainView()
                #endif
            }
        }
        .animation(.default, value: model.phase)
        // Auto-refresh only while the app is in the foreground and a church is open.
        .onChange(of: scenePhase) { _, phase in syncRefresh(phase) }
        .onChange(of: model.phase) { _, _ in syncRefresh(scenePhase) }
    }

    private func syncRefresh(_ phase: ScenePhase) {
        if phase == .active && model.phase == .ready {
            model.startAutoRefresh()
            Task { await model.refreshScreens() }
        } else {
            model.stopAutoRefresh()
        }
    }
}

/// Tab bar on iPhone, sidebar + detail on iPad.
struct MainView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular { PadView() } else { PhoneView() }
    }
}

struct PhoneView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.iPhoneTab) {
            NavigationStack { ScreensView(onSelect: { id in
                model.selectedScreenId = id
                model.iPhoneTab = .remote
            }) }
                .tabItem { Label("Screens", systemImage: "tv.and.mediabox") }
                .tag(AppTab.screens)
            NavigationStack { RemoteTab() }
                .tabItem { Label("Remote", systemImage: "dot.radiowaves.left.and.right") }
                .tag(AppTab.remote)
            NavigationStack { TodayCalendarTab() }   // Calendar: Today | Calendar segments (App/Calendar/CalendarTab.swift)
                .tabItem { Label("Schedule", systemImage: "calendar") }
                .tag(AppTab.today)
            // Only for owners, admins and editors of a church with Kids, Signage or Slides live. Not shown (and not locked) for others.
            if model.canCreate {
                CreateRoot()
                    .tabItem { Label("Create", systemImage: "square.and.pencil") }
                    .tag(AppTab.create)
            }
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
    }
}

/// The Remote tab on iPhone: pick a screen, then control it.
struct RemoteTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let screen = model.selectedScreen {
                RemoteView(screen: screen)
            } else {
                ContentUnavailableView("No screen selected", systemImage: "tv",
                                       description: Text("Choose a screen on the Screens tab."))
            }
        }
        .navigationTitle(model.selectedScreen?.screen.displayName ?? "Remote")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { ScreenPickerMenu() }
            ToolbarItem(placement: .topBarTrailing) { AddMediaButton() }
        }
    }
}

struct ScreenPickerMenu: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        Menu {
            Picker("Screen", selection: $model.selectedScreenId) {
                ForEach(model.screens) { s in
                    Text(s.screen.displayName).tag(Optional(s.id))
                }
            }
        } label: {
            Label("Choose screen", systemImage: "tv")
        }
        .accessibilityLabel("Choose screen")
    }
}

enum PadSelection: Hashable {
    case screen(UUID), today, calendar, create, media, settings
}

struct PadView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: PadSelection?
    @State private var showMedia = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Screens") {
                    ForEach(model.screens) { info in
                        PadScreenRow(info: info).tag(PadSelection.screen(info.id))
                    }
                    if model.screens.isEmpty {
                        Text(model.isLoading ? "Loading…" : "No screens yet").foregroundStyle(.secondary)
                    }
                }
                Section("More") {
                    Label("Today", systemImage: "calendar").tag(PadSelection.today)
                    if !(model.church?.modules.isEmpty ?? true) { Label("Calendar", systemImage: "calendar.day.timeline.left").tag(PadSelection.calendar) }
                    if model.canCreate { Label("Create", systemImage: "square.and.pencil").tag(PadSelection.create) }
                    if model.canAddMedia { Label("Add media", systemImage: "photo.badge.plus").tag(PadSelection.media) }
                    Label("Settings", systemImage: "gearshape").tag(PadSelection.settings)
                }
            }
            .navigationTitle(model.church?.organization.name ?? "Church TV OS")
            .refreshable { await model.refreshScreens() }
            .overlay(alignment: .bottom) {
                if let e = model.loadError { Banner(text: e, style: .error).padding() }
            }
        } detail: {
            if selection == .create {
                CreateRoot()
            } else {
            NavigationStack {
                switch selection {
                case .screen(let id):
                    if let s = model.screens.first(where: { $0.id == id }) {
                        RemoteView(screen: s)
                            .navigationTitle(s.screen.displayName)
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar { ToolbarItem(placement: .topBarTrailing) { AddMediaButton() } }
                    } else { placeholder }
                case .today: TodayView()
                case .calendar: CalendarTab()
                case .create: EmptyView()
                case .media: AddMediaView(embedded: true)
                case .settings: SettingsView()
                case nil: placeholder
                }
            }
            }
        }
        .onAppear {
            if selection == nil {
                if CalendarLaunch.opensCalendar { selection = .calendar }   // test launch argument `-calendar`
                else if model.iPhoneTab == .create, model.canCreate { selection = .create }   // test launch argument `-tab create`
                else { selection = model.selectedScreenId.map(PadSelection.screen) }
            }
        }
        .onChange(of: model.selectedScreenId) { _, id in if selection == nil, let id { selection = .screen(id) } }
        .onChange(of: selection) { _, new in
            if case .screen(let id)? = new { model.selectedScreenId = id }
        }
    }

    private var placeholder: some View {
        ContentUnavailableView("Choose a screen", systemImage: "tv", description: Text("Pick a TV in the sidebar to control it."))
    }
}

struct PadScreenRow: View {
    let info: ScreenInfo
    var body: some View {
        HStack(spacing: 10) {
            OnlineDot(online: info.isOnline())
            VStack(alignment: .leading, spacing: 2) {
                Text(info.screen.displayName).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            StateChip(state: info.displayState())
        }
        .accessibilityElement(children: .combine)
    }
    private var subtitle: String {
        if let t = info.status?.title, info.displayState() != .offline, info.displayState() != .idle { return t }
        return info.locationLine
    }
}

struct AddMediaButton: View {
    @Environment(AppModel.self) private var model
    @State private var show = false
    var body: some View {
        if model.canAddMedia {
            Button { show = true } label: { Label("Add media", systemImage: "photo.badge.plus") }
                .sheet(isPresented: $show) { NavigationStack { AddMediaView(embedded: false) } }
        }
    }
}

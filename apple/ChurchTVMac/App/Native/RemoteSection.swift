import SwiftUI
import ChurchTVCore
import ChurchTVEditors

/// Remote control of a TV: next/previous, jump to a slide, blank, stop, start a deck or playlist, send a message.
/// Uses the same remote command protocol as the iPhone app (`send_screen_command`).
struct RemoteSection: View {
    @Environment(MenuModel.self) private var model
    @State private var nav = NavState.shared
    @State private var playNow = false

    private var screen: ScreenInfo? { model.selectedScreen }
    private var enabled: Bool { model.canControl && (screen?.isOnline() ?? false) && (screen?.supportsRemote ?? false) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            if let screen {
                HSplitView {
                    controls(screen).frame(minWidth: 380, idealWidth: 460)
                    outline(screen).frame(minWidth: 260, idealWidth: 320)
                }
            } else {
                ContentUnavailableView("No screens", systemImage: "tv", description: Text("Pair a TV on the Screens page first."))
            }
        }
        .sheet(isPresented: $playNow) { if let screen { PlayNowSheet(screen: screen) } }
        .sheet(isPresented: $nav.showMessageSheet) { MessageSheetMac().environment(model) }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Picker("TV", selection: Binding(get: { model.selectedScreen?.id }, set: { model.selectedScreenId = $0 })) {
                ForEach(model.screens) { Text($0.screen.displayName).tag(Optional($0.id)) }
            }.frame(maxWidth: 280)
            if let s = screen {
                Circle().fill(s.isOnline() ? Color.green : Color.red).frame(width: 9, height: 9)
                StateChip(state: s.displayState())
            }
            Spacer()
            if let e = model.commandError { Text(e).font(.caption).foregroundStyle(.red).lineLimit(2) }
            if !model.canControl { Text("You cannot control TVs").font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func controls(_ screen: ScreenInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(screen.status?.title.flatMap { $0.isEmpty ? nil : $0 } ?? (screen.isOnline() ? "Nothing playing" : "Offline")).font(.title2.weight(.semibold))
                    if let st = screen.status, st.state != .idle, screen.isOnline() {
                        if let label = st.itemLabel, !label.isEmpty { Text(label).foregroundStyle(.secondary) }
                        if let t = st.slideText { Text(t).font(.callout) }
                        ProgressView(value: st.progress)
                    } else if !screen.isOnline() {
                        Text("Last seen \(Formatting.ago(screen.screen.lastSeenAt))").foregroundStyle(.secondary)
                    }
                    if !screen.supportsRemote && screen.isOnline() { Text("Remote control needs TV app 1.5.0 or newer.").font(.caption).foregroundStyle(.orange) }
                }
                HStack(spacing: 12) {
                    big("backward.fill", "Previous") { .previous }
                    big("forward.fill", "Next") { .next }
                }
                HStack(spacing: 12) {
                    Button { send(.blank(on: nil)) } label: {
                        Label(screen.displayState() == .blank ? "Unblank" : "Blank", systemImage: screen.displayState() == .blank ? "tv" : "tv.slash").frame(maxWidth: .infinity)
                    }.disabled(!enabled)
                    Button(role: .destructive) { send(.stop) } label: { Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity) }.disabled(!enabled)
                }.controlSize(.large)
                HStack(spacing: 12) {
                    Button { playNow = true } label: { Label("Start a deck or playlist…", systemImage: "play.fill").frame(maxWidth: .infinity) }.disabled(!enabled)
                    Button { nav.showMessageSheet = true } label: { Label("Send message…", systemImage: "text.bubble").frame(maxWidth: .infinity) }.disabled(!enabled)
                }.controlSize(.large)
                Text("Shortcuts: ⌥⌘→ next, ⌥⌘← previous, ⌥⌘B blank, ⌥⌘M message.").font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
        }
    }

    private func big(_ icon: String, _ title: String, _ cmd: @escaping () -> RemoteCommand) -> some View {
        Button { send(cmd()) } label: { Label(title, systemImage: icon).font(.title3).frame(maxWidth: .infinity, minHeight: 44) }
            .buttonStyle(.borderedProminent).disabled(!enabled)
    }

    private func send(_ c: RemoteCommand) { if let s = screen { Task { await model.send(c, to: s) } } }

    @ViewBuilder private func outline(_ screen: ScreenInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Slides").font(.headline).padding(12)
            Divider()
            if let outline = screen.status?.outline, !outline.isEmpty, screen.isOnline() {
                ScrollViewReader { proxy in
                    List(Array(outline.enumerated()), id: \.offset) { i, label in
                        HStack {
                            Text("\(i + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 26, alignment: .trailing)
                            Text(label).lineLimit(2)
                            Spacer()
                            if i == screen.status?.currentIndex { Image(systemName: "play.fill").foregroundStyle(.tint) }
                        }
                        .padding(.vertical, 2).contentShape(Rectangle()).id(i)
                        .listRowBackground(i == screen.status?.currentIndex ? Color.accentColor.opacity(0.12) : Color.clear)
                        .onTapGesture(count: 2) { if enabled { send(.jump(index: i)) } }
                        .help("Double-click to jump here")
                    }
                    .onChange(of: screen.status?.currentIndex) { _, i in if let i { withAnimation { proxy.scrollTo(i, anchor: .center) } } }
                }
            } else {
                Text("Nothing to jump to.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Play now (decks and playlists)

struct PlayNowSheet: View {
    @Environment(MenuModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let screen: ScreenInfo
    var preselect: PlayNowItem.ID?
    @State private var items: [PlayNowItem] = []
    @State private var selected: PlayNowItem.ID?
    @State private var minutes = 60
    @State private var sending = false
    private let durations = [15, 30, 60, 90, 120, 240, 480]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Play now on \(screen.screen.displayName)").font(.title2.weight(.semibold))
            Picker("Play for", selection: $minutes) { ForEach(durations, id: \.self) { Text(Formatting.minutes($0)).tag($0) } }.frame(maxWidth: 260)
            Text("After that the TV returns to its schedule.").font(.caption).foregroundStyle(.secondary)
            List(selection: $selected) {
                let decks = items.filter { $0.kind == .deck }, lists = items.filter { $0.kind == .playlist }
                if !decks.isEmpty { Section("Slides decks") { ForEach(decks) { Label($0.name, systemImage: "play.rectangle.on.rectangle").tag($0.id) } } }
                if !lists.isEmpty { Section("Kids playlists") { ForEach(lists) { Label($0.name, systemImage: "figure.and.child.holdinghands").tag($0.id) } } }
            }
            .overlay { if items.isEmpty { Text("No decks or playlists available for your church.").foregroundStyle(.secondary) } }
            .frame(minHeight: 220)
            if let e = model.commandError { Text(e).foregroundStyle(.red).font(.caption) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Start") { start() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(selected == nil || sending)
            }
        }
        .padding(20).frame(width: 460, height: 440)
        .task {
            model.commandError = nil
            if let church = model.church { items = (try? await model.service.playNowItems(organizationId: church.id, modules: church.modules)) ?? [] }
            if selected == nil { selected = preselect }
        }
    }

    private func start() {
        guard let item = items.first(where: { $0.id == selected }) else { return }
        sending = true
        Task {
            let ok = await model.send(.start(kind: item.kind, id: item.refId, minutes: minutes), to: screen)
            sending = false
            if ok { dismiss() }
        }
    }
}

/// The editors' "Play now" button: choose a TV and a duration, then start the playlist or deck.
struct EditorPlayNow: View {
    @Environment(MenuModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let target: PlayNowTarget
    @State private var screenId: UUID?
    @State private var minutes = 60
    @State private var sending = false
    private let durations = [15, 30, 60, 90, 120, 240, 480]

    private var name: String { switch target { case .playlist(_, let n), .deck(_, let n): return n } }
    private var online: [ScreenInfo] { model.screens.filter { $0.isOnline() && $0.supportsRemote } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Play “\(name)” now").font(.title3.weight(.semibold))
            if online.isEmpty { Text("No TV is online with remote control right now.").foregroundStyle(.secondary) }
            Picker("TV", selection: $screenId) { ForEach(online) { Text($0.screen.displayName).tag(Optional($0.id)) } }
            Picker("Play for", selection: $minutes) { ForEach(durations, id: \.self) { Text(Formatting.minutes($0)).tag($0) } }
            if let e = model.commandError { Text(e).foregroundStyle(.red).font(.caption) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Start") { start() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(screenId == nil || sending)
            }
        }
        .padding(20).frame(width: 380)
        .onAppear { model.commandError = nil; if screenId == nil { screenId = online.first?.id } }
    }

    private func start() {
        guard let s = model.screens.first(where: { $0.id == screenId }) else { return }
        let command: RemoteCommand
        switch target {
        case .playlist(let id, _): command = .start(kind: .playlist, id: id, minutes: minutes)
        case .deck(let id, _): command = .start(kind: .deck, id: id, minutes: minutes)
        }
        sending = true
        Task { let ok = await model.send(command, to: s); sending = false; if ok { dismiss() } }
    }
}

/// "Send message" as a sheet (menu command ⌥⌘M and the Remote page).
struct MessageSheetMac: View {
    @Environment(MenuModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Send a message").font(.title2.weight(.semibold))
            MessageForm()
            HStack { Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(20).frame(width: 420)
    }
}

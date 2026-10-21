import SwiftUI
import ChurchTVCore

/// The remote for one screen. Works in portrait and landscape.
struct RemoteView: View {
    @Environment(AppModel.self) private var model
    let screen: ScreenInfo

    @State private var confirmStop = false
    @State private var showPlayNow = false
    @State private var showMessage = false

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height && geo.size.width > 600
            Group {
                if landscape {
                    HStack(alignment: .top, spacing: 16) {
                        ScrollView { VStack(spacing: 14) { header; warnings; controls } .padding() }
                            .frame(maxWidth: geo.size.width * 0.5)
                        jumpSection.frame(maxWidth: .infinity)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 14) { header; warnings; controls; jumpSection }
                            .padding()
                    }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .confirmationDialog("Stop \(screen.screen.displayName)?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Stop playing", role: .destructive) { send(.stop) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The TV goes back to its normal schedule.")
        }
        .sheet(isPresented: $showPlayNow) { PlayNowSheet(screen: screen) }
        .sheet(isPresented: $showMessage) { MessageSheet(screen: screen) }
    }

    // MARK: Pieces

    private var status: ScreenStatus? { screen.status }
    private var state: ScreenDisplayState { screen.displayState() }
    private var controlsEnabled: Bool { screen.supportsRemote && model.canControl }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                OnlineDot(online: screen.isOnline())
                Text(screen.locationLine.isEmpty ? screen.screen.displayName : screen.locationLine)
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                StateChip(state: state)
            }
            if let st = status, state != .offline, state != .idle {
                Text(st.title ?? "Playing").font(.title3.bold()).lineLimit(2)
                if let label = st.itemLabel, !label.isEmpty { Text(label).font(.headline).foregroundStyle(.secondary).lineLimit(2) }
                if let text = st.slideText {
                    HStack { Text(text).font(.subheadline.monospacedDigit()); Spacer(); Text("\(Int(st.progress * 100))%").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary) }
                    ProgressView(value: st.progress).tint(state.tint)
                }
            } else {
                Text(state == .offline ? "Offline" : "Nothing playing").font(.title3.bold())
                Text(state == .offline ? "Last seen \(Formatting.ago(screen.screen.lastSeenAt))" : "Use Play now to start a deck or playlist.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var warnings: some View {
        ForEach(screen.remoteWarnings(), id: \.self) { Banner(text: $0, style: .warning) }
        if let e = model.commandError { Banner(text: e, style: .error) }
        if !model.canControl { Banner(text: "Your role cannot control screens.", style: .warning) }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                bigButton("Previous", "backward.fill") { send(.previous) }
                bigButton("Next", "forward.fill", prominent: true) { send(.next) }
            }
            HStack(spacing: 12) {
                Button { Haptics.tap(); send(.blank(on: nil)) } label: {
                    Label(state == .blank ? "Show" : "Blank", systemImage: state == .blank ? "eye.fill" : "eye.slash.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered).tint(state == .blank ? .indigo : .accentColor)
                .accessibilityLabel(state == .blank ? "Show the screen again" : "Blank the screen")

                Button(role: .destructive) { Haptics.heavy(); confirmStop = true } label: {
                    Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
            HStack(spacing: 12) {
                Button { showPlayNow = true } label: {
                    Label("Play now", systemImage: "play.rectangle.fill").frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.bordered)
                Button { showMessage = true } label: {
                    Label("Message", systemImage: "text.bubble.fill").frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.bordered)
            }
        }
        .controlSize(.large)
        .disabled(!controlsEnabled)
    }

    private func bigButton(_ title: String, _ symbol: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 30, weight: .bold))
                Text(title).font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 92)
        }
        .buttonStyle(.borderedProminent)
        .tint(prominent ? .accentColor : .gray)
        .accessibilityLabel(title == "Next" ? "Next slide" : "Previous slide")
    }

    @ViewBuilder private var jumpSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Jump to").font(.headline).padding(.horizontal, 4)
            if let outline = status?.outline, !outline.isEmpty, state != .offline {
                let current = status?.currentIndex
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(outline.enumerated()), id: \.offset) { i, label in
                                Button { Haptics.selection(); send(.jump(index: i)) } label: {
                                    HStack(spacing: 12) {
                                        Text("\(i + 1)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary).frame(width: 28, alignment: .trailing)
                                        Text(label).font(.body).multilineTextAlignment(.leading)
                                        Spacer(minLength: 0)
                                        if i == current { Image(systemName: "play.fill").foregroundStyle(.tint).accessibilityHidden(true) }
                                    }
                                    .padding(.horizontal, 14).padding(.vertical, 12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(i == current ? Color.accentColor.opacity(0.18) : Color.clear)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .id(i)
                                .accessibilityLabel("Slide \(i + 1), \(label)")
                                .accessibilityAddTraits(i == current ? [.isSelected] : [])
                                Divider().padding(.leading, 54)
                            }
                        }
                    }
                    .frame(minHeight: 120, maxHeight: 520)
                    .onChange(of: current) { _, new in if let new { withAnimation { proxy.scrollTo(new, anchor: .center) } } }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .disabled(!controlsEnabled)
            } else {
                Text(state == .offline ? "The slide list appears when the TV is online and playing." : "The slide list appears when something is playing.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func send(_ c: RemoteCommand) {
        Task { await model.send(c, to: screen) }
    }
}

// MARK: - Play now

struct PlayNowSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let screen: ScreenInfo
    @State private var minutes = 60
    @State private var selected: PlayNowItem.ID?
    @State private var sending = false
    private let durations = [15, 30, 60, 90, 120, 240, 480]

    var body: some View {
        NavigationStack {
            Form {
                Section("Play for") {
                    Picker("Duration", selection: $minutes) {
                        ForEach(durations, id: \.self) { Text(Formatting.minutes($0)).tag($0) }
                    }
                    Text("After that the TV returns to its schedule.").font(.footnote).foregroundStyle(.secondary)
                }
                let decks = model.playNowItems.filter { $0.kind == .deck }
                let lists = model.playNowItems.filter { $0.kind == .playlist }
                if !decks.isEmpty { Section("Slides decks") { rows(decks) } }
                if !lists.isEmpty { Section("Kids playlists") { rows(lists) } }
                if model.playNowItems.isEmpty {
                    Section { Text("No decks or playlists available for your church.").foregroundStyle(.secondary) }
                }
                if let e = model.commandError { Section { Banner(text: e, style: .error) } }
            }
            .navigationTitle("Play now")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { start() }.disabled(selected == nil || sending)
                }
            }
            .task { model.commandError = nil }
        }
        .presentationDetents([.large])
    }

    private func rows(_ items: [PlayNowItem]) -> some View {
        ForEach(items) { item in
            Button { selected = item.id; Haptics.selection() } label: {
                HStack {
                    Label(item.name, systemImage: item.kind == .deck ? "play.rectangle.on.rectangle" : "figure.and.child.holdinghands")
                        .foregroundStyle(.primary)
                    Spacer()
                    if selected == item.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
                }
            }
            .accessibilityAddTraits(selected == item.id ? [.isSelected] : [])
        }
    }

    private func start() {
        guard let item = model.playNowItems.first(where: { $0.id == selected }) else { return }
        sending = true
        Task {
            let ok = await model.send(.start(kind: item.kind, id: item.refId, minutes: minutes), to: screen)
            sending = false
            if ok { dismiss() }
        }
    }
}

// MARK: - Message

struct MessageSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let screen: ScreenInfo
    @State private var text = ""
    @State private var seconds = 30
    @State private var sending = false
    private let durations = [10, 20, 30, 60, 120, 300]

    var body: some View {
        NavigationStack {
            Form {
                Section("Presets") {
                    ForEach(MessagePreset.allCases) { p in
                        Button { text = p.text; Haptics.selection() } label: {
                            VStack(alignment: .leading) { Text(p.shortName).font(.subheadline.weight(.semibold)); Text(p.text).font(.footnote).foregroundStyle(.secondary) }
                        }.foregroundStyle(.primary)
                    }
                }
                Section {
                    TextField("Type a message", text: $text, axis: .vertical).lineLimit(2...5)
                    Text("\(text.count)/200").font(.caption).foregroundStyle(text.count > 200 ? .red : .secondary)
                } header: { Text("Message") }
                Section("Show for") {
                    Picker("Duration", selection: $seconds) {
                        ForEach(durations, id: \.self) { Text($0 >= 60 ? "\($0 / 60) min" : "\($0) s").tag($0) }
                    }
                }
                if let e = model.commandError { Section { Banner(text: e, style: .error) } }
                Section {
                    Button("Clear message from screen", role: .destructive) { Task { await model.send(.clearMessage, to: screen) } }
                }
            }
            .navigationTitle("Send a message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { send() }.disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || sending)
                }
            }
            .task { model.commandError = nil }
        }
    }

    private func send() {
        sending = true
        Task {
            let ok = await model.send(.message(text: text, seconds: seconds, background: nil), to: screen)
            sending = false
            if ok { dismiss() }
        }
    }
}

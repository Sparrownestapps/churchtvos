import SwiftUI
import AppKit
import ChurchTVCore

/// Contents of the menu bar popover (also shown in the "TV Status" window).
struct MenuBarView: View {
    @Environment(MenuModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var showMessage = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if model.isSignedIn { content } else { signedOut }
            Divider()
            footer
        }
        .frame(width: 380)
        .onAppear { model.viewAppeared() }
        .onDisappear { model.viewDisappeared() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(model.status.swiftUIColor).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                if model.churches.count > 1 {
                    Menu {
                        ForEach(model.churches) { c in
                            Button { Task { await model.choose(c) } } label: {
                                if c.id == model.church?.id { Label(c.organization.name, systemImage: "checkmark") } else { Text(c.organization.name) }
                            }
                        }
                    } label: { Text(model.church?.organization.name ?? "Choose church").font(.headline) }
                        .menuStyle(.borderlessButton).fixedSize()
                } else {
                    Text(model.church?.organization.name ?? "Church TV OS").font(.headline).lineLimit(1)
                }
                Text(model.status.summary + (model.useDemo ? " · demo data" : "")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.useDemo { Text("DEMO").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2).background(.orange.opacity(0.2), in: Capsule()).foregroundStyle(.orange) }
            Button { Task { await model.refreshNow() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).help("Refresh now")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: Signed in

    @ViewBuilder private var content: some View {
        if model.screens.isEmpty {
            Text(model.loadError ?? "No TVs paired to this church yet.").foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 70).padding()
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.screens) { s in
                        ScreenRow(screen: s, selected: s.id == model.selectedScreen?.id)
                        if s.id != model.screens.last?.id { Divider().padding(.leading, 14) }
                    }
                }
            }
            .frame(maxHeight: 420)
            .fixedSize(horizontal: false, vertical: true)
        }
        if let e = model.commandError { Text(e).font(.caption).foregroundStyle(.red).padding(.horizontal, 14).padding(.bottom, 6) }
        if let e = model.loadError, !model.screens.isEmpty { Text(e).font(.caption).foregroundStyle(.red).padding(.horizontal, 14).padding(.bottom, 6) }
        Divider()
        DisclosureGroup(isExpanded: $showMessage) {
            MessageForm()
                .padding(.top, 8)
        } label: {
            Label("Send message…", systemImage: "text.bubble").font(.callout.weight(.medium))
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .disabled(model.screens.isEmpty || !model.canControl)
    }

    private var signedOut: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.questionmark").font(.system(size: 34)).foregroundStyle(.secondary)
            Text("Not signed in").font(.headline)
            Text(model.bridgeNote ?? "Sign in once on the website in the app window. The menu bar connects by itself.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack {
                Button("Open dashboard") { openMain() }.buttonStyle(.borderedProminent)
                Button("Use demo data") { Task { await model.setDemo(true) } }
            }
        }
        .padding(18).frame(maxWidth: .infinity)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 4) {
            Button("Open dashboard") { openMain() }
            Button("Control page") { model.web.open(.control); openMain(reload: false) }
            Spacer()
            Menu {
                Toggle("Use demo data", isOn: Binding(get: { model.useDemo }, set: { v in Task { await model.setDemo(v) } }))
                Button("Settings…") { NSApp.activate(ignoringOtherApps: true); openSettings() }
                if model.isSignedIn || model.useDemo { Button(model.useDemo ? "Leave demo" : "Sign out") { Task { await model.signOut() } } }
                Divider()
                Button("Quit Church TV OS") { NSApp.terminate(nil) }
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize()
        }
        .buttonStyle(.link)
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    private func openMain(reload: Bool = true) {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - One TV

struct ScreenRow: View {
    @Environment(MenuModel.self) private var model
    let screen: ScreenInfo
    let selected: Bool

    private var state: ScreenDisplayState { screen.displayState() }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(screen.isOnline() ? Color.green : Color.red).frame(width: 8, height: 8)
                Text(screen.screen.displayName).font(.callout.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 4)
                StateChip(state: state)
            }
            Text(nowShowing).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            HStack(spacing: 6) {
                control("backward.fill", "Previous slide") { RemoteCommand.previous }
                control("forward.fill", "Next slide") { RemoteCommand.next }
                Button { Task { await model.send(.blank(on: nil), to: screen) } } label: {
                    Label(state == .blank ? "Unblank" : "Blank", systemImage: state == .blank ? "tv" : "tv.slash")
                }
                .disabled(!enabled).help("Blank or unblank the TV")
                Button(role: .destructive) { Task { await model.send(.stop, to: screen) } } label: { Label("Stop", systemImage: "stop.fill") }
                    .disabled(!enabled).help("Stop what is playing")
                Spacer()
                if !screen.supportsRemote && screen.isOnline() {
                    Text("Update TV app").font(.caption2).foregroundStyle(.orange).help("Remote control needs TV app 1.5.0 or newer")
                }
            }
            .controlSize(.small).labelStyle(.titleAndIcon)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(selected ? Color.accentColor.opacity(0.08) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { model.selectedScreenId = screen.id }
    }

    private var enabled: Bool { model.canControl && screen.isOnline() && screen.supportsRemote }

    private func control(_ icon: String, _ help: String, _ cmd: @escaping () -> RemoteCommand) -> some View {
        Button { Task { await model.send(cmd(), to: screen) } } label: { Image(systemName: icon) }
            .disabled(!enabled).help(help)
    }

    /// "Sunday 10:30 Service · Slide 4 of 16", the item label, or why nothing is showing.
    private var nowShowing: String {
        if !screen.isOnline() { return "Offline · last seen \(Formatting.ago(screen.screen.lastSeenAt))" }
        guard let st = screen.status, st.state != .idle else { return "Nothing playing" }
        var parts: [String] = []
        if let t = st.title, !t.isEmpty { parts.append(t) }
        if let n = st.slideText { parts.append(n) }
        var line = parts.joined(separator: " · ")
        if let label = st.itemLabel, !label.isEmpty { line += (line.isEmpty ? "" : "\n") + label }
        return line.isEmpty ? st.state.label : line
    }
}

struct StateChip: View {
    let state: ScreenDisplayState
    private var color: Color {
        switch state {
        case .offline: return .red
        case .stale: return .orange
        case .idle: return .gray
        case .playing: return .green
        case .blank: return .purple
        case .message: return .blue
        }
    }
    var body: some View {
        Text(state.label).font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.16), in: Capsule()).foregroundStyle(color)
    }
}

// MARK: - Send message

struct MessageForm: View {
    @Environment(MenuModel.self) private var model
    @State private var text = ""
    @State private var seconds = 30
    @State private var sent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("TV", selection: Binding(get: { model.selectedScreen?.id }, set: { model.selectedScreenId = $0 })) {
                ForEach(model.screens) { Text($0.screen.displayName).tag(Optional($0.id)) }
            }
            TextField("Message to show on the TV", text: $text, axis: .vertical).lineLimit(2...3).textFieldStyle(.roundedBorder)
            HStack {
                Menu("Presets") {
                    ForEach(MessagePreset.allCases) { p in Button(p.shortName) { text = p.text } }
                }.fixedSize()
                Picker("For", selection: $seconds) {
                    ForEach([10, 20, 30, 60, 120], id: \.self) { Text("\($0) s").tag($0) }
                }.fixedSize()
                Spacer()
                Text("\(text.count)/200").font(.caption).foregroundStyle(text.count > 200 ? .red : .secondary)
            }
            HStack {
                Button("Clear message") { if let s = model.selectedScreen { Task { await model.send(.clearMessage, to: s) } } }
                Spacer()
                if sent { Text("Sent").font(.caption).foregroundStyle(.green) }
                Button("Send") {
                    guard let s = model.selectedScreen else { return }
                    Task {
                        if await model.send(.message(text: text, seconds: seconds, background: nil), to: s) {
                            text = ""; sent = true
                            try? await Task.sleep(for: .seconds(2)); sent = false
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 200 || model.selectedScreen == nil)
            }
        }
        .controlSize(.small)
    }
}

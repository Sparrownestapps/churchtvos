import SwiftUI
import ChurchTVCore

extension ScreenDisplayState {
    /// Chip colours; the label text always carries the meaning too (not colour alone).
    var tint: Color {
        switch self {
        case .offline: return .red
        case .stale: return .orange
        case .idle: return .gray
        case .playing: return .green
        case .blank: return .indigo
        case .message: return .blue
        }
    }
    var symbol: String {
        switch self {
        case .offline: return "wifi.slash"
        case .stale: return "exclamationmark.triangle.fill"
        case .idle: return "moon.zzz.fill"
        case .playing: return "play.fill"
        case .blank: return "rectangle.fill"
        case .message: return "text.bubble.fill"
        }
    }
}

struct StateChip: View {
    let state: ScreenDisplayState
    var body: some View {
        Label(state.label, systemImage: state.symbol)
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(state.tint.opacity(0.18), in: Capsule())
            .foregroundStyle(state.tint)
            .accessibilityLabel("State: \(state.label)")
    }
}

struct OnlineDot: View {
    let online: Bool
    var body: some View {
        Circle()
            .fill(online ? Color.green : Color.red)
            .frame(width: 10, height: 10)
            .accessibilityLabel(online ? "Online" : "Offline")
    }
}

struct ModuleBadge: View {
    let module: String?
    var body: some View {
        if let m = module.flatMap(AppModule.init(rawValue:)) {
            Label(m.displayName, systemImage: m.symbol).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// A banner for warnings and errors.
struct Banner: View {
    enum Style { case warning, error, info }
    let text: String
    var style: Style = .warning
    var systemImage: String?

    private var color: Color { style == .error ? .red : style == .warning ? .orange : .blue }
    private var icon: String { systemImage ?? (style == .info ? "info.circle.fill" : "exclamationmark.triangle.fill") }

    var body: some View {
        Label {
            Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

extension ScreenInfo {
    /// What to tell the user when the remote cannot be trusted right now (nil = all good).
    func remoteWarnings(now: Date = Date()) -> [String] {
        var w: [String] = []
        if !supportsRemote {
            let v = screen.appVersion ?? "an unknown version"
            w.append("This TV runs app \(v). Remote control needs TV app \(Config.minimumRemoteTVVersion) or newer. Update the Church TV OS app on the TV.")
        }
        if !isOnline(now: now) {
            w.append("This TV is offline (last seen \(Formatting.ago(screen.lastSeenAt, now: now))). Commands are dropped if the TV is off for more than a minute.")
        } else if status != nil, isStatusStale(now: now), supportsRemote {
            w.append("The TV has not reported what it is showing for a while. The slide shown here may be out of date.")
        }
        return w
    }
}

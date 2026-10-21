import SwiftUI
import ChurchTVCore

struct ScreensView: View {
    @Environment(AppModel.self) private var model
    var onSelect: (UUID) -> Void

    private let columns = [GridItem(.adaptive(minimum: 320), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let e = model.loadError { Banner(text: e, style: .error) }
                if model.isDemo { Banner(text: "Demo mode: sample data, nothing is sent to a real TV.", style: .info, systemImage: "sparkles") }
                if model.screens.isEmpty {
                    if model.isLoading {
                        ProgressView().padding(.top, 60)
                    } else {
                        ContentUnavailableView("No screens yet", systemImage: "tv",
                                               description: Text("Pair a TV from the website, then it will show up here."))
                    }
                } else {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(model.screens) { info in
                            Button { onSelect(info.id) } label: { ScreenCard(info: info) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                if let t = model.lastRefresh {
                    Text("Updated \(Formatting.ago(t)) · refreshes every 3 seconds")
                        .font(.caption2).foregroundStyle(.secondary).padding(.top, 4)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(model.church?.organization.name ?? "Screens")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await model.refreshScreens() }
    }
}

struct ScreenCard: View {
    let info: ScreenInfo

    var body: some View {
        let now = Date()
        let state = info.displayState(now: now)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                OnlineDot(online: info.isOnline(now: now))
                Text(info.screen.displayName).font(.headline).lineLimit(2)
                Spacer(minLength: 6)
                StateChip(state: state)
            }
            HStack(spacing: 10) {
                if !info.locationLine.isEmpty {
                    Label(info.locationLine, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                ModuleBadge(module: info.status?.module ?? info.screen.defaultModule)
            }

            if let st = info.status, state != .offline, state != .idle {
                VStack(alignment: .leading, spacing: 4) {
                    Text(st.title ?? "Playing").font(.subheadline.weight(.semibold)).lineLimit(2)
                    if let label = st.itemLabel, !label.isEmpty {
                        Text(label).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    }
                    if let text = st.slideText {
                        HStack {
                            Text(text).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        ProgressView(value: st.progress).tint(state.tint)
                            .accessibilityLabel("Progress").accessibilityValue(text)
                    }
                }
            } else if state == .offline {
                Text("Last seen \(Formatting.ago(info.screen.lastSeenAt, now: now))").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("Nothing playing right now").font(.subheadline).foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                if !info.supportsRemote {
                    Label("TV app \(info.screen.appVersion ?? "?") · needs \(Config.minimumRemoteTVVersion)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                } else if let u = info.status?.updatedAt {
                    Text("Updated \(Formatting.ago(u, now: now))").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(state: state))
        .accessibilityHint("Opens the remote")
        .accessibilityAddTraits(.isButton)
    }

    private func accessibilityText(state: ScreenDisplayState) -> String {
        var parts = [info.screen.displayName, state.label]
        if !info.locationLine.isEmpty { parts.append(info.locationLine) }
        if let t = info.status?.title, state != .offline, state != .idle { parts.append("Showing \(t)") }
        if let s = info.status?.itemLabel, state != .offline, state != .idle { parts.append(s) }
        if let s = info.status?.slideText, state != .offline, state != .idle { parts.append(s) }
        if !info.supportsRemote { parts.append("TV app too old for remote control") }
        return parts.joined(separator: ", ")
    }
}

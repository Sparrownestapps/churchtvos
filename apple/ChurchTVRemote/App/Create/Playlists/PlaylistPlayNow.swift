import SwiftUI
import ChurchTVCore

/// "Play now" for a saved Kids playlist: pick a TV (skipped when there is only one), then the existing Play now sheet starts it
/// with the `playlist` kind. Signage playlists cannot be started from the remote (the back end only starts decks and Kids playlists).
struct PlaylistPlayNowFlow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let playlistId: UUID
    @State private var chosen: ScreenInfo?

    private var itemId: String { PlayNowItem(kind: .playlist, refId: playlistId, name: "").id }

    var body: some View {
        if model.screens.count == 1, let only = model.screens.first {
            PlayNowSheet(screen: only, preselect: itemId)
        } else {
            NavigationStack {
                List {
                    Section {
                        ForEach(model.screens) { info in
                            Button { chosen = info } label: {
                                HStack {
                                    OnlineDot(online: info.isOnline())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(info.screen.displayName).foregroundStyle(.primary)
                                        if !info.locationLine.isEmpty { Text(info.locationLine).font(.caption).foregroundStyle(.secondary) }
                                    }
                                    Spacer()
                                    StateChip(state: info.displayState())
                                }
                            }
                        }
                    } header: { Text("Choose a TV") } footer: {
                        if model.screens.isEmpty { Text("No TVs are set up for this church yet.") }
                    }
                }
                .navigationTitle("Play now")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
                .sheet(item: $chosen) { PlayNowSheet(screen: $0, preselect: itemId) }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

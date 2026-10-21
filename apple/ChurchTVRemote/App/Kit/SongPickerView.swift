import SwiftUI
import ChurchTVCore

/// Picks a song from the church's library (search by title, author or section label; shows how many sections and TV slides it has).
/// Present it in a sheet; `onSelect` gets the chosen song and the picker dismisses itself.
///
/// ```swift
/// .sheet(isPresented: $picking) { SongPickerView(selectedId: slide.songId) { song in ... } }
/// ```
struct SongPickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Song id (text) to mark as the current choice.
    var selectedId: String?
    var onSelect: (Song) -> Void
    @State private var search = ""
    @State private var loading = false

    private var songs: [Song] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let all = model.content.songs
        guard !q.isEmpty else { return all }
        return all.filter { $0.title.lowercased().contains(q) || ($0.authors ?? "").lowercased().contains(q) || $0.sections.contains { $0.label.lowercased().contains(q) } }
    }

    var body: some View {
        NavigationStack {
            List {
                if let current = selectedId, !current.isEmpty, model.content.songLookup[current.lowercased()] == nil, model.content.supportLoaded {
                    Section { Banner(text: "The song used now is not in the library any more. Choose another.", style: .warning) }
                }
                ForEach(songs) { song in
                    Button { onSelect(song); Haptics.selection(); dismiss() } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(song.title).font(.headline).foregroundStyle(.primary)
                                Text(subtitle(song)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if song.id.uuidString.lowercased() == selectedId?.lowercased() {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint).accessibilityLabel("Selected")
                            }
                        }
                    }
                }
                if songs.isEmpty {
                    if loading { HStack { ProgressView(); Text("Loading songs…").foregroundStyle(.secondary) } }
                    else if model.content.songs.isEmpty {
                        ContentUnavailableView("No songs yet", systemImage: "music.note.list",
                                               description: Text("Add songs on the Songs page of the website, then come back."))
                    } else { ContentUnavailableView.search(text: search) }
                }
            }
            .navigationTitle("Choose a song")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search songs")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task {
                loading = true
                await model.content.loadSupport()
                loading = false
            }
        }
    }

    private func subtitle(_ s: Song) -> String {
        let slides = SongExpander.expand(s).count
        var parts = ["\(s.sections.count) \(s.sections.count == 1 ? "section" : "sections")", "\(slides) \(slides == 1 ? "slide" : "slides")"]
        if let a = s.authors, !a.isEmpty { parts.insert(a, at: 0) }
        return parts.joined(separator: " · ")
    }
}

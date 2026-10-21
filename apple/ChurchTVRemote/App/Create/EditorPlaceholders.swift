import SwiftUI
import ChurchTVCore

// PLACEHOLDERS. The next build-2 agents replace the BODY of each view below (keep the type name and the initialiser, so the
// Create section and the Play now flow keep compiling) and move the finished view into its own file:
//   PlaylistEditorView -> Create/PlaylistEditorView.swift   (playlist editor agent)
//   DeckEditorView, ThemeEditorView -> Create/DeckEditorView.swift, Create/ThemeEditorView.swift   (deck/theme editor agent)
//   ScheduleSheet -> Create/ScheduleSheet.swift   (scheduling agent)
// Delete the placeholder from this file when you move it. See "Build 2 architecture" in apple/README.md for the contract.

/// Edits a Kids or Signage playlist. Pushed by the Create list (`CreateRoute.playlist`).
/// `playlist` is the working copy: a new draft (`isNew`) is inserted on first save, an existing one is updated.
/// Save with `model.content.save(draft, kind:)` and compare `draft != original` for unsaved changes.
struct PlaylistEditorView: View {
    @Environment(AppModel.self) private var model
    let kind: PlaylistKind
    let playlist: PlaylistDraft

    var body: some View {
        List {
            Section {
                Label("The playlist editor is coming in this build.", systemImage: "hammer.fill").foregroundStyle(.orange)
                LabeledContent("Name", value: playlist.name)
                LabeledContent("Type", value: kind.title)
                LabeledContent("Items", value: "\(playlist.items.count)")
                LabeledContent("Available to", value: model.content.siteName(playlist.siteId))
                if playlist.isNew { Text("New, not saved yet.").foregroundStyle(.secondary) }
            }
            if !playlist.items.isEmpty {
                Section("Items (read only)") {
                    ForEach(playlist.items) { item in
                        HStack(spacing: 12) {
                            PlaylistItemPreview(item: item, songs: model.content.songLookup)
                                .frame(width: 72)
                            VStack(alignment: .leading) {
                                Text(item.title.isEmpty ? (item.typeName?.label ?? "Unknown item") : item.title).lineLimit(1)
                                Text(item.typeName?.label ?? "Unknown type").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(playlist.name.isEmpty ? "New playlist" : playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.content.loadSupport() }
    }
}

/// Edits a deck. Pushed by the Create list (`CreateRoute.deck`). Same conventions as `PlaylistEditorView`
/// (save with `model.content.save(draft)`).
struct DeckEditorView: View {
    @Environment(AppModel.self) private var model
    let deck: DeckDraft

    var body: some View {
        List {
            Section {
                Label("The deck editor is coming in this build.", systemImage: "hammer.fill").foregroundStyle(.orange)
                LabeledContent("Name", value: deck.name)
                LabeledContent("Slides", value: "\(deck.slides.count)")
                LabeledContent("Theme", value: model.content.theme(id: deck.themeId)?.name ?? "None")
                LabeledContent("Loops", value: deck.loops ? "Yes" : "No")
                LabeledContent("Available to", value: model.content.siteName(deck.siteId))
                if deck.isNew { Text("New, not saved yet.").foregroundStyle(.secondary) }
            }
            if !deck.slides.isEmpty {
                Section("Slides (read only)") {
                    let theme = model.content.theme(id: deck.themeId)?.config
                    ForEach(deck.slides) { slide in
                        SlidePreview(slide: slide, deckBackground: deck.background, theme: theme, songs: model.content.songLookup)
                            .frame(width: 140)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .navigationTitle(deck.name.isEmpty ? "New deck" : deck.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.content.loadSupport() }
    }
}

/// Edits a theme. Pushed by the Create list (`CreateRoute.theme`). The theme row already exists (it is created with its name
/// before the editor opens); save changes with `model.content.save(theme)`.
struct ThemeEditorView: View {
    @Environment(AppModel.self) private var model
    let theme: SlideTheme

    var body: some View {
        List {
            Section {
                Label("The theme editor is coming in this build.", systemImage: "hammer.fill").foregroundStyle(.orange)
                LabeledContent("Name", value: theme.name)
                LabeledContent("Font", value: theme.config.resolved.font.rawValue.capitalized)
                LabeledContent("Text colour", value: theme.config.resolved.textColor)
            }
            Section("Sample") {
                SlidePreview(frame: .text(layout: .titleBody, title: "Welcome to church", body: "We're glad you're here. Service starts at 10:00.", align: nil, color: nil),
                             theme: theme.config.resolved,
                             background: BackgroundResolver.resolve(slide: nil, deck: nil, theme: theme.config.background))
                    .frame(maxWidth: 360)
            }
        }
        .navigationTitle(theme.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Schedules a deck or playlist (one-off or repeating). Presented as a sheet from the Create list swipe actions and from the
/// "Play now" sheet. The scheduling agent builds the real form (locations come from `model.content.locations`, filtered by
/// `Location.uses(target.module)`).
struct ScheduleSheet: View {
    @Environment(\.dismiss) private var dismiss
    let target: ScheduleTarget

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "calendar.badge.clock").font(.system(size: 48)).foregroundStyle(.tint).accessibilityHidden(true)
                Text("Scheduling is coming in this build.").font(.headline)
                Text("This will schedule \"\(target.name)\" on your TVs.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle("Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

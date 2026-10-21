import SwiftUI
import ChurchTVCore

/// "Import PowerPoint, PDF or pictures" button for the deck and playlist editors. Opens `ImportSheet`; when the import finishes the
/// pages are added to the editor's own draft (the editor's Save then keeps them). Hidden for people who cannot add media.
public struct ImportButton: View {
    @Environment(ContentModel.self) private var model
    @State private var showing = false
    @State private var flowToken = UUID()

    private let target: ImportTarget
    private let compact: Bool
    /// Signage playlists are not imported into (the website's importer is for decks and Kids playlists).
    private let supported: Bool
    private let readOnly: Bool
    private let siteId: UUID?
    private let count: () -> Int
    private let insert: (ImportResult) -> Void

    /// For the deck editor. `onInserted` gets the id of the first new slide, to select it.
    public init(deckSlides: Binding<[DeckSlide]>, siteId: UUID? = nil, readOnly: Bool = false, onInserted: ((String) -> Void)? = nil) {
        target = .deck
        supported = true
        self.siteId = siteId
        compact = true
        self.readOnly = readOnly
        count = { deckSlides.wrappedValue.count }
        insert = { result in
            let new = ImportBuilder.deckSlides(pages: result.pages, seconds: result.seconds, existing: deckSlides.wrappedValue)
            var list = deckSlides.wrappedValue
            ImportBuilder.insert(new, into: &list, placement: result.placement)
            deckSlides.wrappedValue = list
            if let first = new.first { onInserted?(first.id) }
        }
    }

    /// For the Kids and Signage playlist editors.
    public init(playlistItems: Binding<[PlaylistItem]>, kind: PlaylistKind, siteId: UUID? = nil, readOnly: Bool = false) {
        target = .kids
        self.siteId = siteId
        self.supported = kind == .kids
        compact = false
        self.readOnly = readOnly
        count = { playlistItems.wrappedValue.count }
        insert = { result in
            let new = ImportBuilder.playlistItems(pages: result.pages, seconds: result.seconds)
            var list = playlistItems.wrappedValue
            ImportBuilder.insert(new, into: &list, placement: result.placement)
            playlistItems.wrappedValue = list
        }
    }

    public var body: some View {
        if supported && !readOnly && model.canAddMedia {
            Button { flowToken = UUID(); showing = true } label: {
                Label(compact ? "Import" : "Import PowerPoint, PDF or pictures", systemImage: "square.and.arrow.down").lineLimit(1).fixedSize()
            }
            .accessibilityHint("Adds slides from a PowerPoint file, a PDF or pictures")
            .sheet(isPresented: $showing) {
                ImportSheet(flow: ImportFlow(target: target, content: model, existingCount: count(), siteId: siteId, apply: insert))
                    .id(flowToken)
            }
            #if DEBUG
            .task { if ProcessInfo.processInfo.arguments.contains("-importopen") { showing = true } }
            #endif
        }
    }
}

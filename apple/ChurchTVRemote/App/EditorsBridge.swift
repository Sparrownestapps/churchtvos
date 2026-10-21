import SwiftUI
import ChurchTVCore
import ChurchTVEditors

// The content editors live in the ChurchTVEditors package (apple/ChurchTVEditors) so the Mac app can use them too.
// These aliases keep the old names working in every Remote file without an import. Create/CreateView.swift aliases the Create section.
typealias Banner = ChurchTVEditors.Banner
typealias Haptics = ChurchTVEditors.Haptics
typealias ScheduleSheet = ChurchTVEditors.ScheduleSheet
typealias AddMediaView = ChurchTVEditors.AddMediaView
#if DEBUG
typealias KitGalleryView = ChurchTVEditors.KitGalleryView
#endif

/// The Remote is the editors' host: it supplies the session, the TVs and Play now.
extension AppModel: ContentHost {
    var supportsPlayNow: Bool { true }

    func playNowView(_ target: PlayNowTarget) -> AnyView? {
        switch target {
        case .playlist(let id, _): return AnyView(PlaylistPlayNowFlow(playlistId: id))
        case .deck(let id, let name): return AnyView(DeckPlayNowSheet(deckId: id, name: name))
        }
    }
}

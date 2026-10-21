import SwiftUI
import ChurchTVCore

/// What the Play now sheet should start.
public enum PlayNowTarget: Sendable {
    case playlist(id: UUID, name: String)
    case deck(id: UUID, name: String)
}

/// The app that embeds the editors. The Remote's `AppModel` conforms to it; the Mac app supplies its own.
/// The editors read these through `ContentModel`, inside SwiftUI bodies, so an `@Observable` host keeps them live.
@MainActor
public protocol ContentHost: AnyObject {
    /// The signed in service (Supabase or the demo `MockService`).
    var service: any ChurchService { get }
    /// The church being edited (nil until one is chosen).
    var church: ChurchAccess? { get }
    /// The church's TVs (for schedule time zones and Play now). May be empty.
    var screens: [ScreenInfo] { get }
    /// Called after content changed that the host shows elsewhere (Play now list, schedule list). May be a no-op.
    func loadPlayNow() async
    func loadSchedule() async
    /// Whether Play now buttons are offered. A host that can start a deck or playlist on a TV returns true and implements `playNowView`.
    var supportsPlayNow: Bool { get }
    func playNowView(_ target: PlayNowTarget) -> AnyView?
    /// Debug launch argument for screenshots: which Create list to open first (`kids`, `signage`, `slides`, `themes`).
    var initialCreateSection: String? { get }
}

public extension ContentHost {
    var screens: [ScreenInfo] { [] }
    func loadPlayNow() async {}
    func loadSchedule() async {}
    var supportsPlayNow: Bool { false }
    func playNowView(_ target: PlayNowTarget) -> AnyView? { nil }
    var initialCreateSection: String? { nil }
}

import SwiftUI
import Observation
import ChurchTVCore

/// The sidebar sections of the native app. Visibility mirrors the website's `buildNav` (role, modules, platform admin).
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case screens, remote, calendar, media, songs, kids, signage, slides, themes, people, settings, sites, admin
    var id: String { rawValue }

    enum Group: String, CaseIterable {
        case operate = "Operate", library = "Library", create = "Create", manage = "Manage", admin = "Admin"
    }

    var title: String {
        switch self {
        case .screens: return "Screens"
        case .remote: return "Remote"
        case .calendar: return "Calendar"
        case .media: return "Media"
        case .songs: return "Songs"
        case .kids: return "Kids playlists"
        case .signage: return "Signage playlists"
        case .slides: return "Slides decks"
        case .themes: return "Themes"
        case .people: return "People"
        case .settings: return "Settings"
        case .sites: return "Sites & Locations"
        case .admin: return "Admin"
        }
    }

    var symbol: String {
        switch self {
        case .screens: return "tv"
        case .remote: return "dot.radiowaves.left.and.right"
        case .calendar: return "calendar"
        case .media: return "photo.on.rectangle.angled"
        case .songs: return "music.note.list"
        case .kids: return "figure.and.child.holdinghands"
        case .signage: return "rectangle.on.rectangle"
        case .slides: return "play.rectangle.on.rectangle"
        case .themes: return "paintpalette"
        case .people: return "person.2"
        case .settings: return "gearshape"
        case .sites: return "mappin.and.ellipse"
        case .admin: return "building.columns"
        }
    }

    var group: Group {
        switch self {
        case .screens, .remote, .calendar: return .operate
        case .media, .songs: return .library
        case .kids, .signage, .slides, .themes: return .create
        case .people, .settings, .sites: return .manage
        case .admin: return .admin
        }
    }

    /// Sections that still open the website in the fallback pane.
    var isWebFallback: Bool { self == .sites }
    /// Hash route of the website page, for the fallback pane.
    var webRoute: String? { self == .sites ? "sites" : nil }

    /// ⌘1...⌘9 and ⌘0 for the first ten visible sections.
    func isVisible(church: ChurchAccess?, isPlatformAdmin: Bool) -> Bool {
        if self == .admin { return isPlatformAdmin }
        guard let church else { return false }
        let any = !church.modules.isEmpty
        switch self {
        case .screens: return true
        case .remote: return any                       // canControlNav: every role, with a live module
        case .calendar, .media: return any
        case .songs: return church.modules.contains(.kids) || church.modules.contains(.slides)
        case .kids: return church.editableModules.contains(.kids)
        case .signage: return church.editableModules.contains(.signage)
        case .slides, .themes: return church.editableModules.contains(.slides)
        case .people, .settings, .sites: return PeopleRules.canManage(church.role)
        case .admin: return false
        }
    }

    static func visible(church: ChurchAccess?, isPlatformAdmin: Bool) -> [AppSection] {
        allCases.filter { $0.isVisible(church: church, isPlatformAdmin: isPlatformAdmin) }
    }

    /// Debug launch argument `-section <name>` (screenshots).
    static var launchSection: AppSection? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: "-section"), i + 1 < a.count else { return nil }
        return AppSection(rawValue: a[i + 1])
    }
}

/// Where the user is, shared by the window, the menu commands and the toolbar.
@MainActor
@Observable
final class NavState {
    static let shared = NavState()
    private static let key = "lastSection"

    var section: AppSection {
        didSet { UserDefaults.standard.set(section.rawValue, forKey: Self.key) }
    }
    /// Menu commands ask the current section to show these sheets.
    var showPairSheet = false
    var showMessageSheet = false
    var sidebarVisible = NavigationSplitViewVisibility.all

    private init() {
        section = AppSection.launchSection ?? AppSection(rawValue: UserDefaults.standard.string(forKey: Self.key) ?? "") ?? .screens
    }

    func go(_ s: AppSection) { section = s }
}

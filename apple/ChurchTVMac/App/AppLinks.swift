import Foundation
import ChurchTVCore

enum AppLinks {
    static let dashboard = Config.websiteURL
    static let help = URL(string: "https://app.churchtvos.com/help/")!
    static let privacy = Config.privacyURL
    static let terms = Config.termsURL
    static let deleteAccount = Config.deleteAccountURL

    /// Website sections (hash routes). Pages the signed-in person cannot see fall back to the first visible page.
    enum Section: String, CaseIterable {
        case screens, control, calendar, songs
        var title: String {
            switch self { case .screens: "Screens"; case .control: "Control"; case .calendar: "Calendar"; case .songs: "Songs" }
        }
    }
}

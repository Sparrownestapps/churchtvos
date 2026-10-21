import Foundation

/// Demo media have no real files: their `url` is `demo:<kind>/<RRGGBB>/<RRGGBB>` and apps draw a gradient (or an icon) for them.
public enum DemoMedia {
    public static func url(_ kind: MediaKind, _ a: String, _ b: String) -> String { "demo:\(kind.rawValue)/\(a)/\(b)" }

    /// The kind and two colours (with '#') of a demo URL, or nil for a real URL.
    public static func parse(_ url: String) -> (kind: MediaKind, color1: String, color2: String)? {
        guard url.hasPrefix("demo:") else { return nil }
        let parts = url.dropFirst(5).split(separator: "/").map(String.init)
        guard parts.count == 3, let kind = MediaKind(rawValue: parts[0]) else { return nil }
        return (kind, "#" + parts[1], "#" + parts[2])
    }
}

/// In-memory content for demo mode: sample playlists, decks, themes, songs and media, plus the edits made during the demo.
struct MockContentStore {
    var kids: [Playlist]
    var signage: [Playlist]
    var decks: [SlideDeck]
    var themes: [SlideTheme]
    var songs: [Song]
    var media: [MediaItem]
    var folders: [MediaFolder]
    var sites: [Site]
    var locations: [Location]

    static let org = MockService.churchId
    static func uuid(_ group: Int, _ n: Int) -> UUID { UUID(uuidString: String(format: "D0D0D0D0-0000-4000-8000-%04d00000%03d", group, n))! }
    static func mediaId(_ n: Int) -> UUID { uuid(3, n) }

    static func make() -> MockContentStore {
        let now = Date()
        func ago(_ h: Double) -> Date { now.addingTimeInterval(-h * 3600) }

        // Sites and locations
        let site1 = Site(id: UUID(uuidString: "D0D0D0D0-0000-4000-8000-0000000000B1")!, name: "Downtown Campus", timezone: TimeZone.current.identifier)
        let site2 = Site(id: UUID(uuidString: "D0D0D0D0-0000-4000-8000-0000000000B2")!, name: "Eastside Campus", timezone: TimeZone.current.identifier)
        let locations = [
            Location(id: uuid(5, 1), name: "Auditorium", siteId: site1.id, modules: ["slides"]),
            Location(id: uuid(5, 2), name: "Kids Wing", siteId: site1.id, modules: ["kids"]),
            Location(id: uuid(5, 3), name: "Lobby", siteId: site1.id, modules: ["signage"]),
            Location(id: uuid(5, 4), name: "Youth Loft", siteId: site1.id, modules: ["slides", "signage"]),
            Location(id: uuid(5, 5), name: "Eastside Gym", siteId: site2.id, modules: ["kids", "slides"]),
        ]

        // Folders
        func folder(_ n: Int, _ module: AppModule, _ name: String, parent: UUID? = nil) -> MediaFolder {
            MediaFolder(id: uuid(2, n), module: module.rawValue, parentId: parent, name: name)
        }
        let fBackgrounds = folder(1, .slides, "Backgrounds"), fSeries = folder(2, .slides, "Sermon series")
        let fWeek1 = folder(3, .slides, "Anchored", parent: fSeries.id)
        let fStories = folder(4, .kids, "Bible stories"), fGames = folder(5, .kids, "Games")
        let fNotices = folder(6, .signage, "Announcements")
        let folders = [fBackgrounds, fSeries, fWeek1, fStories, fGames, fNotices]

        // Media
        func m(_ n: Int, _ module: AppModule, _ folder: UUID?, _ title: String, _ kind: MediaKind, _ a: String, _ b: String, mb: Double) -> MediaItem {
            MediaItem(id: mediaId(n), organizationId: org, module: module.rawValue, folderId: folder, title: title, kind: kind,
                      storagePath: "demo/\(n)", url: DemoMedia.url(kind, a, b), sizeBytes: Int64(mb * 1_048_576), createdAt: ago(Double(n)))
        }
        let media = [
            m(1, .slides, fBackgrounds.id, "Welcome background", .image, "1f3a5f", "2e7d5b", mb: 1.8),
            m(2, .slides, fBackgrounds.id, "Sunrise", .image, "f59e0b", "b3261e", mb: 2.4),
            m(3, .slides, fBackgrounds.id, "Night sky", .image, "101820", "7c3aed", mb: 1.2),
            m(4, .slides, fWeek1.id, "Anchored title graphic", .image, "0b3c5d", "328cc1", mb: 0.9),
            m(5, .slides, nil, "Worship loop", .video, "111827", "1d4ed8", mb: 64),
            m(6, .slides, nil, "Countdown motion", .video, "3b0764", "be185d", mb: 38),
            m(7, .slides, nil, "Gathering music", .audio, "6b7280", "374151", mb: 7.5),
            m(8, .slides, nil, "Upbeat pre-service mix", .audio, "6b7280", "374151", mb: 11.2),
            m(10, .kids, fStories.id, "David and Goliath", .video, "2e7d5b", "1d4ed8", mb: 96),
            m(11, .kids, fStories.id, "Welcome to Kids", .video, "d9480f", "f59e0b", mb: 42),
            m(12, .kids, fGames.id, "Freeze dance slide", .image, "7c3aed", "f59e0b", mb: 0.7),
            m(13, .kids, nil, "Memory verse: Joshua 1:9", .image, "1d4ed8", "2e7d5b", mb: 0.8),
            m(14, .kids, nil, "Calm-down music", .audio, "6b7280", "374151", mb: 5.1),
            m(20, .signage, fNotices.id, "Coffee bar", .image, "6f4e37", "c8a27a", mb: 1.1),
            m(21, .signage, fNotices.id, "Kids check-in", .image, "2e7d5b", "f59e0b", mb: 1.4),
            m(22, .signage, nil, "Welcome loop", .video, "1f3a5f", "328cc1", mb: 30),
        ]
        func mid(_ n: Int) -> String { mediaId(n).uuidString.lowercased() }
        func url(_ n: Int) -> String { media.first { $0.id == mediaId(n) }!.url }

        // Songs (public domain)
        func sec(_ id: String, _ label: String, _ text: String) -> SongSection { SongSection(id: id, label: label, text: text) }
        let songs = [
            Song(id: uuid(4, 1), title: "Amazing Grace", organizationId: org, authors: "John Newton", copyright: "Public Domain", sections: [
                sec("s1", "Verse 1", "Amazing grace, how sweet the sound\nThat saved a wretch like me\nI once was lost, but now am found\nWas blind, but now I see"),
                sec("s2", "Verse 2", "'Twas grace that taught my heart to fear\nAnd grace my fears relieved\nHow precious did that grace appear\nThe hour I first believed"),
                sec("s3", "Chorus", "My chains are gone, I've been set free\nMy God, my Savior has ransomed me"),
            ], arrangement: ["s1", "s2", "s3", "s1"], linesPerSlide: 2, source: "manual", updatedAt: ago(30)),
            Song(id: uuid(4, 2), title: "It Is Well With My Soul", organizationId: org, authors: "Horatio Spafford", copyright: "Public Domain", sections: [
                sec("s1", "Verse 1", "When peace like a river attendeth my way\nWhen sorrows like sea billows roll\nWhatever my lot, Thou hast taught me to say\nIt is well, it is well with my soul"),
                sec("s2", "Chorus", "It is well (it is well)\nWith my soul (with my soul)\nIt is well, it is well with my soul"),
            ], linesPerSlide: 0, source: "paste", updatedAt: ago(70)),
            Song(id: uuid(4, 3), title: "Holy, Holy, Holy", organizationId: org, authors: "Reginald Heber", copyright: "Public Domain", sections: [
                sec("s1", "Verse 1", "Holy, holy, holy! Lord God Almighty!\nEarly in the morning our song shall rise to Thee\nHoly, holy, holy! Merciful and mighty!\nGod in three persons, blessed Trinity!"),
            ], linesPerSlide: 2, source: "manual", updatedAt: ago(90)),
            Song(id: uuid(4, 4), title: "Be Thou My Vision", organizationId: org, authors: "Traditional Irish", copyright: "Public Domain", sections: [
                sec("s1", "Verse 1", "Be Thou my vision, O Lord of my heart\nNaught be all else to me, save that Thou art\nThou my best thought, by day or by night\nWaking or sleeping, Thy presence my light"),
                sec("s2", "Verse 2", "Be Thou my wisdom, and Thou my true word\nI ever with Thee and Thou with me, Lord"),
            ], linesPerSlide: 0, source: "file", updatedAt: ago(120)),
            Song(id: uuid(4, 5), title: "This Little Light of Mine", organizationId: org, authors: "Traditional", copyright: "Public Domain", sections: [
                sec("s1", "Verse", "This little light of mine\nI'm gonna let it shine"),
                sec("s2", "Chorus", "Let it shine, let it shine, let it shine"),
                sec("s3", "Empty", ""),
            ], arrangement: ["s1", "s2", "s1", "s2"], linesPerSlide: 0, source: "manual", updatedAt: ago(150)),
        ]
        func sid(_ n: Int) -> String { uuid(4, n).uuidString.lowercased() }

        // Themes
        let classic = SlideTheme(id: uuid(6, 1), organizationId: org, name: "Classic dark blue", config: ThemePreset.all[0].config, createdAt: ago(300), updatedAt: ago(200))
        let warm = SlideTheme(id: uuid(6, 2), organizationId: org, name: "Warm light", config: ThemePreset.all[1].config, createdAt: ago(300), updatedAt: ago(250))

        // Kids playlists (ids match MockService.braveList / gardenList so "Play now" lines up)
        let brave = Playlist(id: MockService.braveList.id, organizationId: org, siteId: nil, name: MockService.braveList.name, items: [
            PlaylistItem(.video(MediaClip(title: "Welcome to Kids", url: url(11), mediaId: mid(11), writesSeconds: false))),
            PlaylistItem(.countdown(CountdownItem(countdown: CountdownSettings(title: "Service starts in", mode: .duration, seconds: 300, audio: CountdownAudio(mediaId: mid(14), url: url(14)), atZero: .hold, ifPassed: .zero)))),
            PlaylistItem(.lyrics(LyricsItem(title: "This Little Light of Mine", songId: sid(5), showTitle: true))),
            PlaylistItem(.video(MediaClip(title: "David and Goliath", url: url(10), mediaId: mid(10), writesSeconds: false))),
            PlaylistItem(.image(MediaClip(title: "Memory verse: Joshua 1:9", url: url(13), mediaId: mid(13), seconds: nil))),
            PlaylistItem(.youtube(YouTubeItem(title: "Brave Like David (YouTube)", videoId: "dQw4w9WgXcQ", start: 12))),
            PlaylistItem(.stream(StreamItem(title: "Main service live", url: "https://example.com/live/main.m3u8", seconds: nil, audio: false, fallback: .skip))),
        ], createdAt: ago(100), updatedAt: ago(5))
        let garden = Playlist(id: MockService.gardenList.id, organizationId: org, siteId: site1.id, name: MockService.gardenList.name, items: [
            PlaylistItem(.image(MediaClip(title: "Freeze dance slide", url: url(12), mediaId: mid(12), seconds: 20))),
            PlaylistItem(.lyrics(LyricsItem(title: "Jesus Loves Me", slides: ["Jesus loves me! This I know,\nFor the Bible tells me so.", "Little ones to Him belong;\nThey are weak, but He is strong."], showTitle: false))),
            PlaylistItem(.countdown(CountdownItem(countdown: CountdownSettings(title: "Clean up time", seconds: 120)))),
        ], createdAt: ago(80), updatedAt: ago(26))

        // Signage playlists
        let lobby = Playlist(id: uuid(7, 1), organizationId: org, siteId: nil, name: "Lobby loop", items: [
            PlaylistItem(.sign(SignItem(title: "Welcome home!", subtext: "Services at 9:00 and 10:30", background: "#1f3a5f", seconds: 10, align: .center, logo: true))),
            PlaylistItem(.image(MediaClip(title: "Coffee bar", url: url(20), mediaId: mid(20), seconds: 8))),
            PlaylistItem(.image(MediaClip(title: "Kids check-in", url: url(21), mediaId: mid(21), seconds: 8))),
            PlaylistItem(.video(MediaClip(title: "Welcome loop", url: url(22), mediaId: mid(22), seconds: nil))),
            PlaylistItem(.stream(StreamItem(title: "Sanctuary camera", url: "https://example.com/live/sanctuary.m3u8", seconds: 30, audio: false, fallback: .hold))),
        ], createdAt: ago(60), updatedAt: ago(3))
        let board = Playlist(id: uuid(7, 2), organizationId: org, siteId: site1.id, name: "Welcome board", items: [
            PlaylistItem(.sign(SignItem(title: "Next steps", subtext: "Ask at the info desk", background: "#2e7d5b", seconds: 12, align: .left, logo: false))),
            PlaylistItem(.image(MediaClip(title: "Coffee bar", url: url(20), mediaId: mid(20), seconds: 10))),
        ], createdAt: ago(50), updatedAt: ago(48))

        // Decks (ids match MockService.sundayDeck / christmasDeck)
        func slide(_ n: Int, _ content: DeckSlide.Content, bg: SlideBackground? = nil, notes: String? = nil) -> DeckSlide {
            DeckSlide(id: "s_demo\(n)", background: bg, notes: notes, content: content)
        }
        let sunday = SlideDeck(id: MockService.sundayDeck.id, organizationId: org, siteId: nil, name: MockService.sundayDeck.name, themeId: classic.id, slides: [
            slide(1, .countdown(CountdownSettings(title: "Service starts in", mode: .duration, seconds: 300, audio: CountdownAudio(mediaId: mid(7), url: url(7)), atZero: .hold, ifPassed: .zero))),
            slide(2, .text(TextSlideContent(title: "Welcome", body: "We're glad you're here.\nService starts at 10:30.", layout: .titleBody))),
            slide(3, .song(SongSlideContent(songId: sid(1), showTitle: true))),
            slide(4, .text(TextSlideContent(title: "Pastor Sam", body: "Lead Pastor", layout: .lowerThird)), bg: .image(mediaId: mid(2), url: url(2), dim: 0.35)),
            slide(5, .media(MediaSlideContent(mediaId: mid(4), url: url(4), mediaKind: .image, fit: .contain)), notes: "Sermon series graphic"),
            slide(6, .song(SongSlideContent(songId: sid(2), showTitle: false))),
            slide(7, .stream(StreamSlideContent(title: "Live from Eastside", url: "https://example.com/live/eastside.m3u8", audio: true, fallback: .hold))),
            slide(8, .media(MediaSlideContent(mediaId: mid(5), url: url(5), mediaKind: .video, fit: .cover, audio: true))),
            slide(9, .text(TextSlideContent(title: "Offering", body: "Give online or in the lobby.", layout: .titleBody, align: .left))),
            slide(10, .blank(BlankSlideContent(color: "#000000"))),
        ], loops: false, createdAt: ago(200), updatedAt: ago(6))
        let christmas = SlideDeck(id: MockService.christmasDeck.id, organizationId: org, siteId: site1.id, name: MockService.christmasDeck.name, themeId: warm.id,
                                  background: .gradient("#7c3aed", "#1f3a5f", angle: 160), slides: [
            slide(21, .countdown(CountdownSettings(title: "Candlelight begins at", mode: .until, until: "17:00", atZero: .hold, ifPassed: .zero))),
            slide(22, .text(TextSlideContent(title: "Merry Christmas", body: "Glory to God in the highest", layout: .titleBody))),
            slide(23, .song(SongSlideContent(songId: sid(3), showTitle: true))),
            slide(24, .media(MediaSlideContent(mediaId: mid(3), url: url(3), mediaKind: .image, fit: .cover))),
            slide(25, .blank(BlankSlideContent(color: "#101820"))),
        ], loops: true, createdAt: ago(190), updatedAt: ago(50))

        // Only with the `-ndiseed` launch argument (screenshots): one Kids playlist and one deck that already hold NDI entries.
        var kidsLists = [brave, garden], decks = [sunday, christmas]
        if ProcessInfo.processInfo.arguments.contains("-ndiseed") {
            kidsLists.append(Playlist(id: uuid(7, 9), organizationId: org, siteId: nil, name: "Live camera test (NDI)", items: [
                PlaylistItem(.countdown(CountdownItem(countdown: CountdownSettings(title: "Starting soon", seconds: 60)))),
                PlaylistItem(.ndi(NdiItem(ndi: NdiSettings(title: "Main camera", source: "STUDIO-PC (Camera 1)", address: "192.168.1.50:5961", fit: .fit,
                                                           fallback: .message, fallbackText: "Camera is offline, back soon", maxWaitSeconds: 15)))),
                PlaylistItem(.ndi(NdiItem(ndi: NdiSettings(title: "Stage wide", source: "PTZ-CAM (Stage)", audio: true, fit: .fill, seconds: 120)))),
            ], createdAt: ago(20), updatedAt: ago(2)))
            decks.append(SlideDeck(id: uuid(8, 9), organizationId: org, siteId: nil, name: "NDI camera test", themeId: classic.id, slides: [
                slide(91, .text(TextSlideContent(title: "Welcome", body: "Camera next", layout: .titleBody))),
                slide(92, .ndi(NdiSettings(title: "Main camera", source: "STUDIO-PC (Camera 1)", address: "192.168.1.50:5961", fallback: .message, fallbackText: "Camera is offline, back soon"))),
            ], loops: false, createdAt: ago(20), updatedAt: ago(2)))
        }

        return MockContentStore(kids: kidsLists, signage: [lobby, board], decks: decks, themes: [classic, warm],
                                songs: songs, media: media, folders: folders, sites: [site1, site2], locations: locations)
    }
}

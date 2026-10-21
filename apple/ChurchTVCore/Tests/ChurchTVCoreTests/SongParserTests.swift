import XCTest
@testable import ChurchTVCore

/// Same cases as selfCheck() in dashboard/src/songParsers.ts.
final class SongParserTests: XCTestCase {
    private func summary(_ s: ParsedSong) -> [String] { s.sections.map { "\($0.id)|\($0.label)|\($0.text.components(separatedBy: "\n").count)" } }

    func testLabels() {
        XCTAssertEqual(SongParsers.labelFromLine("verse 1"), "Verse 1")
        XCTAssertEqual(SongParsers.labelFromLine("[Chorus]"), "Chorus")
        XCTAssertEqual(SongParsers.labelFromLine("(Bridge 2)"), "Bridge 2")
        XCTAssertEqual(SongParsers.labelFromLine("PRE-CHORUS:"), "Pre-Chorus")
        XCTAssertEqual(SongParsers.labelFromLine("pre chorus"), "Pre-Chorus")
        XCTAssertEqual(SongParsers.labelFromLine("Verse1"), "Verse 1")
        XCTAssertNil(SongParsers.labelFromLine("Amazing grace"))
    }

    func testPlainWithLabels() {
        let a = SongParsers.parsePlainText("Amazing Grace  \r\n\r\n[Verse 1]\r\nAmazing grace how sweet the sound\r\nThat saved a wretch like me\r\n\r\nCHORUS:\r\nMy chains are gone\r\n\r\n\r\n\r\npre chorus\r\nHold on\r\nCCLI Song # 1234567\r\n(c) 1779 Public Domain\r\n")
        XCTAssertEqual(a.title, "Amazing Grace")
        XCTAssertEqual(a.ccliNumber, "1234567")
        XCTAssertEqual(a.copyright, "(c) 1779 Public Domain")
        XCTAssertEqual(summary(a), ["s1|Verse 1|2", "s2|Chorus|1", "s3|Pre-Chorus|1"])
    }

    func testPlainWithoutLabels() {
        let b = SongParsers.parsePlainText("Line one\nLine two\n\nLine three\n\n\n\nLine four\n© 2020 Someone", titleHint: "My Song")
        XCTAssertEqual(b.title, "My Song")
        XCTAssertEqual(summary(b), ["s1|Section 1|2", "s2|Section 2|1", "s3|Section 3|1"])
        XCTAssertEqual(b.copyright, "© 2020 Someone")
        XCTAssertEqual(SongParsers.parsePlainText("Line one\nLine two").title, "")
        XCTAssertEqual(SongParsers.parsePlainText("Verse 1\n\nA\nB").title, "")
        // a church licence line is dropped, not kept as lyrics
        XCTAssertEqual(SongParsers.parsePlainText("T\n\nLine\nCCLI Licence # 123456").sections.map(\.text), ["Line"])
    }

    func testUsr() {
        let usr = SongParsers.parseUsr("[File]\nType=SongSelect Import File\nVersion=3\n[S A7654321]\nTitle=How Great\nAuthor=Chris Tomlin | Jesse Reeves,Louie Giglio\nCopyright=2004 sixsteps Music\nFields=Verse 1/Chorus\nWords=How great is our God/Sing with me/tHow great is our God/All will see\n")
        XCTAssertEqual(usr.title, "How Great")
        XCTAssertEqual(usr.ccliNumber, "7654321")
        XCTAssertEqual(usr.authors, "Chris Tomlin, Jesse Reeves, Louie Giglio")
        XCTAssertEqual(usr.copyright, "2004 sixsteps Music")
        XCTAssertEqual(usr.sections, [SongSection(id: "s1", label: "Verse 1", text: "How great is our God\nSing with me"),
                                      SongSection(id: "s2", label: "Chorus", text: "How great is our God\nAll will see")])
        XCTAssertEqual(summary(SongParsers.parseUsr("[S A1]\nTitle=X\nFields=Verse 1\nWords=a/b/tc/d")), ["s1|Section 1|2", "s2|Section 2|2"])
        let fallback = SongParsers.parseUsr("Hello\n\nVerse\nWorld")
        XCTAssertEqual(fallback.sections.count, 1)
        XCTAssertEqual(fallback.title, "Hello")
    }

    func testChordPro() {
        let cp = SongParsers.parseChordPro("# comment\n{title: Good Good Father}\n{st: Pat Barrett}\n{author: Anthony Brown}\n{ccli: 7036612}\n{copyright: 2014 Capitol}\n{key: G}\n{start_of_verse: Verse 1}\n[G]Oh, I've heard a thousand [Am7/C]stories\nOf what they think You're like\n{end_of_verse}\n{soc}\n[C]You're a good good [G]Father\n{eoc}\n{c: Bridge}\nLove so deep\n\n{sob}\nTag line\n{end_of_bridge}\n")
        XCTAssertEqual(cp.title, "Good Good Father")
        XCTAssertEqual(cp.authors, "Pat Barrett, Anthony Brown")
        XCTAssertEqual(cp.ccliNumber, "7036612")
        XCTAssertEqual(cp.copyright, "2014 Capitol")
        XCTAssertEqual(cp.sections, [
            SongSection(id: "s1", label: "Verse 1", text: "Oh, I've heard a thousand stories\nOf what they think You're like"),
            SongSection(id: "s2", label: "Chorus", text: "You're a good good Father"),
            SongSection(id: "s3", label: "Bridge", text: "Love so deep"),
            SongSection(id: "s4", label: "Bridge", text: "Tag line"),
        ])
        XCTAssertEqual(SongParsers.parseChordPro("{sov}\nA\n{eov}").sections.first?.label, "Verse")
    }

    func testFilePickerAndHelpers() {
        let f = SongParsers.parseFile(name: "Great_Are_You_Lord.cho", text: "{sov}\nLine\n{eov}")
        XCTAssertEqual(f.kind, "ChordPro")
        XCTAssertEqual(f.song.title, "Great Are You Lord")      // falls back to the file name
        XCTAssertEqual(SongParsers.parseFile(name: "x.usr", text: "[S A1]\nTitle=T\nWords=a").kind, "SongSelect")
        XCTAssertEqual(SongParsers.parseFile(name: "notes.txt", text: "{title: Sneaky}\n{soc}\nA\n{eoc}").kind, "ChordPro")   // looks inside .txt
        XCTAssertEqual(SongParsers.parseFile(name: "plain.txt", text: "Title\n\nLine").song.title, "Title")
    }

    func testNewSectionIdAndExpand() {
        // JS: sections.length + 1 = 3 is taken, so s4
        XCTAssertEqual(SongParsers.newSectionId([SongSection(id: "s1", label: "", text: ""), SongSection(id: "s3", label: "", text: "")]), "s4")
        let a = SongParsers.parsePlainText("Amazing Grace\n\n[Verse 1]\nAmazing grace how sweet the sound\nThat saved a wretch like me\n\nCHORUS:\nMy chains are gone\n\npre chorus\nHold on")
        let slides = SongExpander.expand(sections: a.sections, arrangement: ["s1", "s2", "s1", "zz"], linesPerSlide: 1)
        XCTAssertEqual(slides.map { "\($0.label):\($0.text.replacingOccurrences(of: "\n", with: "/"))" },
                       ["Verse 1:Amazing grace how sweet the sound", "Verse 1:That saved a wretch like me", "Chorus:My chains are gone",
                        "Verse 1:Amazing grace how sweet the sound", "Verse 1:That saved a wretch like me"])
        XCTAssertEqual(SongExpander.expand(sections: a.sections, arrangement: nil, linesPerSlide: 0).count, 3)
    }

    func testDecodeText() {
        XCTAssertEqual(SongParsers.decodeText(Data("héllo".utf8)), "héllo")
        XCTAssertEqual(SongParsers.decodeText(Data([0x63, 0x61, 0x66, 0xE9])), "café")          // Windows Latin-1
        XCTAssertEqual(SongParsers.decodeText("hi".data(using: .utf16)!), "hi")                  // UTF-16 with BOM
    }

    func testDraftRowsAndArrangement() throws {
        let sections = [SongSection(id: "s1", label: "Verse", text: "A  \n"), SongSection(id: "s2", label: " ", text: "B")]
        var d = SongDraft(title: " T ", authors: " ", ccliNumber: " 123 ", sections: sections, arrangement: ["s1", "s2"])
        XCTAssertNil(d.storedArrangement)                       // every section once, in order = default
        d.arrangement = ["s2", "s1", "zz"]
        XCTAssertEqual(d.storedArrangement, ["s2", "s1"])
        let row = d.row(organizationId: UUID())
        XCTAssertEqual(row.title, "T"); XCTAssertNil(row.authors); XCTAssertEqual(row.ccliNumber, "123")
        XCTAssertEqual(row.sections.map(\.text), ["A", "B"]); XCTAssertEqual(row.sections[1].label, "Section")
        let json = String(data: try JSONEncoder().encode(SongDraft(title: "x", sections: sections).row(organizationId: UUID())), encoding: .utf8)!
        XCTAssertTrue(json.contains("\"arrangement\":null"))     // explicit null
        XCTAssertEqual(SongDraft(title: "", sections: sections).problem, "Give the song a title.")
        XCTAssertEqual(SongDraft(title: "t", sections: [SongSection(id: "s1", label: "V", text: " ")]).problem, "Add some words to at least one section.")
        XCTAssertEqual(d.duplicated().title, " T  (copy)")
    }

    func testImportPlanner() {
        let lib = [Song(id: UUID(), title: "Amazing  Grace")]
        XCTAssertNotNil(SongImportPlanner.duplicate(of: " amazing grace ", in: lib))
        XCTAssertEqual(SongImportPlanner.defaultAction(for: "Amazing Grace", in: lib), .skip)
        XCTAssertEqual(SongImportPlanner.defaultAction(for: "New song", in: lib), .import)
        XCTAssertEqual(SongImportPlanner.copyTitle(" X "), "X (copy)")
    }
}

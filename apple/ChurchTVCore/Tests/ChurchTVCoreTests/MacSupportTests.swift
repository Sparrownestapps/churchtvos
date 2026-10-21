import XCTest
@testable import ChurchTVCore

final class MacSupportTests: XCTestCase {
    private func screen(online: Bool, now: Date) -> ScreenInfo {
        let s = Screen(id: UUID(), organizationId: UUID(), locationId: nil, name: "TV", orientation: "landscape", defaultModule: "slides",
                       model: nil, appVersion: "1.5.1", lastSeenAt: online ? now : now.addingTimeInterval(-600))
        return ScreenInfo(screen: s)
    }

    func testRollup() {
        let now = Date()
        XCTAssertEqual(MenuBarStatus.rollup(signedIn: false, screens: [screen(online: true, now: now)], now: now), .signedOut)
        XCTAssertEqual(MenuBarStatus.rollup(signedIn: true, screens: [], now: now), .noScreens)
        XCTAssertEqual(MenuBarStatus.rollup(signedIn: true, screens: [screen(online: true, now: now), screen(online: true, now: now)], now: now), .allOnline)
        XCTAssertEqual(MenuBarStatus.rollup(signedIn: true, screens: [screen(online: true, now: now), screen(online: false, now: now)], now: now), .someOffline)
    }

    func testStorageKey() {
        XCTAssertEqual(WebSessionBridge.projectRef, "gqkefjngblgomuovaivj")
        XCTAssertEqual(WebSessionBridge.storageKey(), "sb-gqkefjngblgomuovaivj-auth-token")
        XCTAssertTrue(WebSessionBridge.isSessionKey("sb-abc-auth-token"))
        XCTAssertFalse(WebSessionBridge.isSessionKey("churchtvos.theme"))
        XCTAssertFalse(WebSessionBridge.isSessionKey("sb-abc-auth-token-code-verifier"))
    }

    private func jwt(exp: Int) -> String {
        func b64(_ s: String) -> String { Data(s.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_") }
        return "\(b64("{\"alg\":\"HS256\"}")).\(b64("{\"exp\":\(exp)}")).sig"
    }

    func testParseCurrentShape() {
        let exp = Int(Date().timeIntervalSince1970) + 3000
        let raw = "{\"access_token\":\"A\",\"refresh_token\":\"R\",\"expires_at\":\(exp),\"token_type\":\"bearer\",\"user\":{\"id\":\"x\"}}"
        let s = WebSessionBridge.parse(raw)
        XCTAssertEqual(s?.accessToken, "A"); XCTAssertEqual(s?.refreshToken, "R")
        XCTAssertEqual(s?.expiresAt, Date(timeIntervalSince1970: TimeInterval(exp)))
        XCTAssertTrue(s!.isFresh())
        XCTAssertFalse(s!.isFresh(now: Date().addingTimeInterval(4000)))
    }

    func testParseWrappedAndJwtFallback() {
        let exp = Int(Date().timeIntervalSince1970) + 100
        let raw = "{\"currentSession\":{\"access_token\":\"\(jwt(exp: exp))\",\"refresh_token\":\"R\"}}"
        let s = WebSessionBridge.parse(raw)
        XCTAssertEqual(s?.expiresAt, Date(timeIntervalSince1970: TimeInterval(exp)))
        XCTAssertNotNil(WebSessionBridge.parse("{\"session\":{\"access_token\":\"a\",\"refresh_token\":\"b\",\"expires_at\":\"123\"}}"))
    }

    func testParseRejectsGarbage() {
        XCTAssertNil(WebSessionBridge.parse(nil))
        XCTAssertNil(WebSessionBridge.parse(""))
        XCTAssertNil(WebSessionBridge.parse("not json"))
        XCTAssertNil(WebSessionBridge.parse("[]"))
        XCTAssertNil(WebSessionBridge.parse("{\"access_token\":\"\",\"refresh_token\":\"r\"}"))
        XCTAssertNil(WebSessionBridge.parse("{\"access_token\":\"a\"}"))
        // Unknown expiry is never "fresh", and the description never leaks tokens.
        let s = WebSession(accessToken: "SECRET", refreshToken: "SECRET2", expiresAt: nil)
        XCTAssertFalse(s.isFresh())
        XCTAssertFalse("\(s)".contains("SECRET"))
    }

    func testLinkRouting() {
        func d(_ u: String, blank: Bool = false, main: Bool = true) -> LinkRouter.Decision { LinkRouter.decide(url: URL(string: u), opensNewWindow: blank, isMainFrame: main) }
        XCTAssertEqual(d("https://app.churchtvos.com/#screens"), .allow)
        XCTAssertEqual(d("https://APP.churchtvos.com/help/"), .allow)
        XCTAssertEqual(d("https://example.com/"), .openExternally)
        XCTAssertEqual(d("https://app.churchtvos.com/install.html", blank: true), .openExternally)
        XCTAssertEqual(d("https://youtu.be/abc", blank: true), .openExternally)
        XCTAssertEqual(d("https://www.youtube.com/embed/x", main: false), .allow)
        XCTAssertEqual(d("https://app.churchtvos.com.evil.com/"), .openExternally)
        XCTAssertEqual(d("mailto:a@b.com"), .openExternally)
        XCTAssertEqual(d("file:///etc/passwd"), .cancel)
        XCTAssertEqual(d("churchtvos://x"), .cancel)
        XCTAssertEqual(d("about:blank"), .allow)
        XCTAssertEqual(LinkRouter.decide(url: nil, opensNewWindow: false), .cancel)
        XCTAssertFalse(LinkRouter.isSafeToOpenExternally(URL(string: "file:///tmp")!))
        XCTAssertTrue(LinkRouter.isSafeToOpenExternally(URL(string: "https://x.com")!))
    }
}

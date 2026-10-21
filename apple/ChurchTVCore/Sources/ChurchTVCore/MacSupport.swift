import Foundation

// Pure logic used by the Mac app (kept here so `swift test` covers it).

// MARK: - Menu bar status roll-up

/// What the menu bar icon's dot shows.
public enum MenuBarStatus: Equatable, Sendable {
    case signedOut        // grey
    case allOnline        // green
    case someOffline      // amber
    case noScreens        // grey: signed in but nothing to watch

    /// - Parameter signedIn: signed in (or demo mode).
    public static func rollup(signedIn: Bool, screens: [ScreenInfo], now: Date = Date()) -> MenuBarStatus {
        guard signedIn else { return .signedOut }
        guard !screens.isEmpty else { return .noScreens }
        return screens.allSatisfy { $0.isOnline(now: now) } ? .allOnline : .someOffline
    }

    public var summary: String {
        switch self {
        case .signedOut: return "Signed out"
        case .allOnline: return "All TVs online"
        case .someOffline: return "Some TVs offline"
        case .noScreens: return "No TVs"
        }
    }
}

// MARK: - Session bridge (website localStorage -> native session)

/// A Supabase session as supabase-js stores it in `localStorage["sb-<project-ref>-auth-token"]`.
/// `description` never prints the tokens.
public struct WebSession: Equatable, Sendable, CustomStringConvertible {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date?
    public init(accessToken: String, refreshToken: String, expiresAt: Date?) {
        self.accessToken = accessToken; self.refreshToken = refreshToken; self.expiresAt = expiresAt
    }
    public var description: String { "WebSession(expiresAt: \(expiresAt.map { "\($0)" } ?? "unknown"))" }

    /// True when the access token is still good for at least `margin` seconds (unknown expiry counts as expired).
    public func isFresh(now: Date = Date(), margin: TimeInterval = 30) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSince(now) > margin
    }
}

public enum WebSessionBridge {
    /// The localStorage key supabase-js uses for this project.
    public static func storageKey(projectRef: String = projectRef) -> String { "sb-\(projectRef)-auth-token" }

    /// Project ref taken from the configured Supabase URL (gqkefjngblgomuovaivj).
    public static var projectRef: String { Config.supabaseURL.host?.split(separator: ".").first.map(String.init) ?? "" }

    /// True for any key of the form `sb-<ref>-auth-token`.
    public static func isSessionKey(_ key: String) -> Bool { key.hasPrefix("sb-") && key.hasSuffix("-auth-token") }

    /// JavaScript that returns the raw stored JSON string (or null). Runs in the page.
    public static var readScript: String { "(window.localStorage.getItem(\(jsString(storageKey()))) || \"\")" }

    /// JavaScript that removes every `sb-*-auth-token` key (used when signing out from the Mac side).
    public static let clearScript = """
    (function(){try{var ks=[];for(var i=0;i<localStorage.length;i++){var k=localStorage.key(i);if(k&&k.indexOf('sb-')===0&&k.slice(-11)==='-auth-token'){ks.push(k);}}ks.forEach(function(k){localStorage.removeItem(k);});return ks.length;}catch(e){return -1;}})()
    """

    private static func jsString(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }

    /// Parses the stored JSON. Accepts the current supabase-js shape (`access_token`, `refresh_token`, `expires_at` in seconds),
    /// a wrapped shape (`currentSession` / `session`), and falls back to the JWT `exp` claim. Returns nil for anything unusable.
    public static func parse(_ raw: String?) -> WebSession? {
        guard let raw, !raw.isEmpty, let data = raw.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data) else { return nil }
        var obj = any as? [String: Any]
        if let inner = obj?["currentSession"] as? [String: Any] { obj = inner }
        else if let inner = obj?["session"] as? [String: Any] { obj = inner }
        guard let o = obj,
              let access = (o["access_token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !access.isEmpty,
              let refresh = (o["refresh_token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !refresh.isEmpty
        else { return nil }
        var expires: Date?
        if let n = o["expires_at"] as? NSNumber { expires = Date(timeIntervalSince1970: n.doubleValue) }
        else if let s = o["expires_at"] as? String, let d = Double(s) { expires = Date(timeIntervalSince1970: d) }
        if expires == nil { expires = jwtExpiry(access) }
        return WebSession(accessToken: access, refreshToken: refresh, expiresAt: expires)
    }

    /// `exp` claim of a JWT, or nil.
    public static func jwtExpiry(_ jwt: String) -> Date? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = obj["exp"] as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: exp.doubleValue)
    }
}

// MARK: - Link routing

/// Decides whether a navigation stays in the Mac app's web view or goes to the default browser.
public enum LinkRouter {
    public enum Decision: Equatable, Sendable { case allow, openExternally, cancel }

    /// Hosts that stay in the app window.
    public static let internalHosts: Set<String> = ["app.churchtvos.com"]

    public static func isInternal(_ url: URL?) -> Bool {
        guard let url, let host = url.host?.lowercased() else { return false }
        return internalHosts.contains(host)
    }

    /// - Parameters:
    ///   - opensNewWindow: the link has `target=_blank` / `window.open` (no target frame).
    ///   - isMainFrame: false for iframes (always allowed; embeds such as YouTube previews).
    public static func decide(url: URL?, opensNewWindow: Bool, isMainFrame: Bool = true) -> Decision {
        guard let url else { return .cancel }
        let scheme = url.scheme?.lowercased() ?? ""
        switch scheme {
        case "about", "blob", "data", "javascript": return isMainFrame && opensNewWindow ? .cancel : .allow
        case "http", "https": break
        case "mailto", "tel": return .openExternally
        default: return .cancel
        }
        if !isMainFrame && !opensNewWindow { return .allow }
        if opensNewWindow { return .openExternally }   // target=_blank always goes to the default browser
        return isInternal(url) ? .allow : .openExternally
    }

    /// Whether a URL may be opened with `NSWorkspace` (never `file:` or custom schemes).
    public static func isSafeToOpenExternally(_ url: URL) -> Bool {
        ["http", "https", "mailto", "tel"].contains(url.scheme?.lowercased() ?? "")
    }
}

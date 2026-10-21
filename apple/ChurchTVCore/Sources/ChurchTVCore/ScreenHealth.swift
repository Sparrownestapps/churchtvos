import Foundation

/// Online / stale / version rules in one place (unit tested).
public enum ScreenHealth {
    /// Online = checked in within the last 90 seconds.
    public static func isOnline(lastSeen: Date?, now: Date = Date()) -> Bool {
        guard let lastSeen else { return false }
        return now.timeIntervalSince(lastSeen) <= Config.onlineWindow
    }

    /// A status row is stale when older than 60 seconds (or missing a timestamp).
    public static func isStatusStale(updatedAt: Date?, now: Date = Date()) -> Bool {
        guard let updatedAt else { return true }
        return now.timeIntervalSince(updatedAt) > Config.statusStaleAfter
    }

    /// TV app 1.5.0 or newer understands remote commands. Unknown version (never reported) = unsupported.
    public static func supportsRemote(appVersion: String?) -> Bool {
        guard let appVersion else { return false }
        return AppVersion.isAtLeast(appVersion, Config.minimumRemoteTVVersion)
    }
}

/// Dotted-number version comparison ("1.10.0" > "1.9.2"; "1.5" == "1.5.0"; suffixes like "-beta" are ignored).
public enum AppVersion {
    public static func components(_ v: String) -> [Int] {
        // Keep the leading numeric run of each dotted part, drop a leading "v".
        var s = v.trimmingCharacters(in: .whitespaces)
        if s.lowercased().hasPrefix("v") { s.removeFirst() }
        return s.split(separator: ".").map { part in
            Int(part.prefix(while: { $0.isNumber })) ?? 0
        }
    }

    public static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let x = components(a), y = components(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }

    public static func isAtLeast(_ a: String, _ b: String) -> Bool { compare(a, b) != .orderedAscending }
}

/// Human-readable text helpers.
public enum Formatting {
    /// "just now", "12 s ago", "3 min ago", "2 h ago", "4 d ago", "never".
    public static func ago(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "never" }
        let s = Int(now.timeIntervalSince(date))
        if s < 5 { return "just now" }
        if s < 60 { return "\(s) s ago" }
        if s < 3600 { return "\(s / 60) min ago" }
        if s < 86400 { return "\(s / 3600) h ago" }
        return "\(s / 86400) d ago"
    }

    /// 90 -> "1:30", 3700 -> "1:01:40"
    public static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// "45 minutes", "2 hours", "1 h 30 min"
    public static func minutes(_ m: Int) -> String {
        if m < 60 { return "\(m) min" }
        let h = m / 60, r = m % 60
        return r == 0 ? "\(h) h" : "\(h) h \(r) min"
    }

    public static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    /// Turns an error into a sentence for people. Server `raise exception` texts arrive as PostgREST messages and are shown as is.
    public static func message(for error: Error) -> String {
        if let e = error as? ChurchError { return e.message }
        if (error as? URLError)?.code == .notConnectedToInternet { return "You appear to be offline." }
        if let e = error as? URLError, e.code == .timedOut { return "The server took too long to answer. Try again." }
        let desc = (error as NSError).userInfo[NSLocalizedDescriptionKey] as? String ?? error.localizedDescription
        // PostgREST errors are decoded by the SDK; extract a readable "message" if the text still looks like JSON.
        if let data = desc.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let m = obj["message"] as? String { return m }
        return desc
    }
}

/// Errors with texts that are safe to show.
public struct ChurchError: Error, LocalizedError, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

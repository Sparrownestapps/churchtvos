import Foundation

// EXPERIMENTAL NDI source (a camera or computer on the same network). Shared by Kids playlist items (`"type": "ndi"`) and Slides deck
// slides (`"kind": "ndi"`). The JSON and the rules must match NDI-CONTRACT.md, dashboard/src/ndiLogic.ts and the database function
// `ndi_check` (supabase/migrations/20261023000001_ndi_experimental.sql). Only offered when `organizations.ndi_enabled` is true.

public enum NdiFit: String, Hashable, Sendable, CaseIterable { case fit, fill }
public enum NdiFallback: String, Hashable, Sendable, CaseIterable { case skip, message }

/// The fields of one NDI source. Keys this model does not understand stay in the owning item's / slide's `extra`.
public struct NdiSettings: Hashable, Sendable {
    /// Label for lists and the remote (optional).
    public var title: String
    /// The NDI source name exactly as NDI lists it, "MACHINE (Source)". Required.
    public var source: String
    /// Optional host or IP with an optional :port, for networks where discovery does not work.
    public var address: String?
    public var audio: Bool
    public var fit: NdiFit
    public var fallback: NdiFallback
    /// Shown when `fallback` is `.message`. Empty: the TV says "Waiting for the live feed…".
    public var fallbackText: String?
    /// 3 to 120: how long the TV waits for the source before the fallback applies.
    public var maxWaitSeconds: Int
    /// 1 to 86400, nil = until Next.
    public var seconds: Int?

    public static let defaultMaxWait = 15
    public static let maxWaitRange = 3...120
    public static let secondsRange = 1...86400

    public init(title: String = "", source: String = "", address: String? = nil, audio: Bool = false, fit: NdiFit = .fit, fallback: NdiFallback = .skip,
                fallbackText: String? = nil, maxWaitSeconds: Int = NdiSettings.defaultMaxWait, seconds: Int? = nil) {
        self.title = title; self.source = source; self.address = address; self.audio = audio; self.fit = fit; self.fallback = fallback
        self.fallbackText = fallbackText; self.maxWaitSeconds = maxWaitSeconds; self.seconds = seconds
    }

    // MARK: Validation (ndiProblem / ndi_check)

    /// Host name or IP with an optional :port (1 to 65535). Empty is fine (discovery by name).
    public static func isValidAddress(_ address: String) -> Bool {
        let a = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.isEmpty { return true }
        guard a.range(of: #"^[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?(:\d{1,5})?$"#, options: .regularExpression) != nil else { return false }
        if let colon = a.lastIndex(of: ":"), let port = Int(a[a.index(after: colon)...]) { return (1...65535).contains(port) }
        return true
    }

    /// What is wrong with these settings, or nil. Same texts as the website.
    public var problem: String? {
        if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "needs the NDI source name, for example \"STUDIO-PC (Camera 1)\"." }
        if source.utf16.count > 200 { return "the NDI source name is too long." }
        if !Self.isValidAddress(address ?? "") { return "the address must be a host name or IP address, with an optional :port (for example 192.168.1.50:5961), and no spaces." }
        if !Self.maxWaitRange.contains(maxWaitSeconds) { return "\"Wait for the source\" must be a whole number from 3 to 120 seconds." }
        if let s = seconds, !Self.secondsRange.contains(s) { return "\"Show for\" must be a whole number of seconds from 1 to 86400, or empty." }
        if fallback == .message, (fallbackText ?? "").utf16.count > 200 { return "the fallback message is too long (200 characters)." }
        return nil
    }

    /// Trims, and drops optional fields that are empty or do not apply (cleanNdi).
    public func cleaned() -> NdiSettings {
        var c = self
        c.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        c.source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = (address ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        c.address = a.isEmpty ? nil : a
        let t = (fallbackText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        c.fallbackText = fallback == .message && !t.isEmpty ? t : nil
        return c
    }

    // MARK: JSON

    /// Reads (and removes) the NDI keys. A missing key takes the contract default.
    init(consuming o: inout RawObject) {
        self.init(title: o.takeString("title") ?? "", source: o.takeString("source") ?? "", address: o.takeString("address"), audio: o.takeBool("audio") ?? false,
                  fit: o.takeEnum("fit") ?? .fit, fallback: o.takeEnum("fallback") ?? .skip, fallbackText: o.takeString("fallback_text"),
                  maxWaitSeconds: o.takeInt("max_wait_seconds") ?? Self.defaultMaxWait, seconds: o.takeInt("seconds"))
    }

    /// Writes every key. `address` and `fallback_text` are written only when set (absent, not null); `seconds` is an explicit null for "until Next".
    func write(into o: inout RawObject, writesTitle: Bool) {
        if writesTitle || !title.isEmpty { o["title"] = .string(title) }
        o["source"] = .string(source)
        o["address"] = address.map(RawJSON.string)
        o["audio"] = .bool(audio)
        o["fit"] = .string(fit.rawValue)
        o["fallback"] = .string(fallback.rawValue)
        o["fallback_text"] = fallbackText.map(RawJSON.string)
        o["max_wait_seconds"] = .number(Double(maxWaitSeconds))
        o.putNullable("seconds", seconds)
    }

    /// Text for lists: the title, else the source name.
    public var label: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        let s = source.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? "NDI source" : s
    }
}

/// A Kids (or Signage) playlist item of type `ndi`.
public struct NdiItem: Hashable, Sendable {
    public var ndi: NdiSettings
    public var extra: RawObject
    public init(ndi: NdiSettings = NdiSettings(), extra: RawObject = [:]) { self.ndi = ndi; self.extra = extra }
}

public enum NdiText {
    public static let label = "NDI source (experimental)"
    public static let badge = "EXPERIMENTAL"
    /// Same wording as NDI_NEEDS_NOTE in the website.
    public static let needsNote = "Experimental. Only works on TVs running the special Church TV OS \"NDI\" build (version ends in -ndi). The normal store app skips this item."
    public static let networkHelp = "The TV and the NDI source must be on the same network. NDI finds sources by broadcasting on the local network, and that doesn't cross VLANs or subnets. If the TV is on a different network from the camera or computer, type the source's address too. A TV on Wi-Fi should receive NDI|HX (NDI High Efficiency), not full-bandwidth NDI, which needs a wired TV. Sound is off unless you turn it on. If the source drops, the TV waits the number of seconds above, then follows \"If the source isn't available\"."
    public static let previewNote = "No preview on the phone. The picture appears on the TV."
    /// Shown instead of the editor when the church does not have the flag.
    public static let offNote = "NDI sources are switched off for this church, so this one is not shown on the TV and cannot be changed. You can delete it."
    public static func fitNote(_ fit: NdiFit) -> String { fit == .fill ? "cropped to fill the screen" : "whole picture, with bars if the shapes differ" }
}

public enum NdiRules {
    /// The database guard (`ndi_guard_content`): with the flag off, NDI entries may stay or be removed, never added or changed.
    /// Order is ignored (the TV skips the entries anyway); returns true when `new` has an NDI entry that `old` does not.
    public static func addsOrChanges(old: [NdiSettings], new: [NdiSettings]) -> Bool {
        var remaining = old
        for n in new {
            if let i = remaining.firstIndex(of: n) { remaining.remove(at: i) } else { return true }
        }
        return false
    }

    public static let notEnabledMessage = "NDI sources are an experimental feature that is not enabled for this church"
}

public extension PlaylistItem {
    var ndiSettings: NdiSettings? { if case .ndi(let n) = content { return n.ndi }; return nil }
    static func newNdi() -> PlaylistItem { .init(.ndi(NdiItem())) }
}

public extension DeckSlide {
    var ndiSettings: NdiSettings? { if case .ndi(let n) = content { return n }; return nil }
}

public extension Array where Element == PlaylistItem {
    var ndiEntries: [NdiSettings] { compactMap(\.ndiSettings) }
}
public extension Array where Element == DeckSlide {
    var ndiEntries: [NdiSettings] { compactMap(\.ndiSettings) }
}

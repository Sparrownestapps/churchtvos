import Foundation

/// Audio that plays during a countdown (a file from the media library, `media.kind = 'audio'`).
/// Same JSON as `CountdownAudio` in dashboard/src/slidesTypes.ts.
public struct CountdownAudio: Hashable, Sendable, RawObjectCodable {
    public var mediaId: String
    public var url: String
    /// 0...1, default 0.8.
    public var volume: Double?
    /// Repeat until zero, default true.
    public var loop: Bool?
    /// Fade out over the last N seconds (0...10), default 3.
    public var fadeSeconds: Int?
    /// "Finish exactly at zero": start a shorter track late so it ends at 0:00. Default false.
    public var alignEnd: Bool?
    public var extra: RawObject

    public static let defaultVolume = 0.8
    public static let defaultFadeSeconds = 3

    /// What the website's picker writes when a track is chosen.
    public init(mediaId: String, url: String, volume: Double? = defaultVolume, loop: Bool? = true,
                fadeSeconds: Int? = defaultFadeSeconds, alignEnd: Bool? = false, extra: RawObject = [:]) {
        self.mediaId = mediaId; self.url = url; self.volume = volume; self.loop = loop
        self.fadeSeconds = fadeSeconds; self.alignEnd = alignEnd; self.extra = extra
    }

    public init(object: RawObject) {
        var o = object
        mediaId = o.takeString("media_id") ?? ""
        url = o.takeString("url") ?? ""
        volume = o.takeDouble("volume")
        loop = o.takeBool("loop")
        fadeSeconds = o.takeInt("fade_seconds")
        alignEnd = o.takeBool("align_end")
        extra = o
    }

    public var object: RawObject {
        var o = extra
        o["media_id"] = .string(mediaId)
        o["url"] = .string(url)
        o.put("volume", volume); o.put("loop", loop); o.put("fade_seconds", fadeSeconds); o.put("align_end", alignEnd)
        return o
    }

    public var effectiveVolume: Double { volume ?? Self.defaultVolume }
    public var effectiveLoop: Bool { loop ?? true }
    public var effectiveFadeSeconds: Int { fadeSeconds ?? Self.defaultFadeSeconds }
    public var effectiveAlignEnd: Bool { alignEnd ?? false }
}

public enum CountdownMode: String, Hashable, Sendable, CaseIterable { case duration, until }
public enum CountdownAtZero: String, Hashable, Sendable, CaseIterable { case next, hold }
public enum CountdownIfPassed: String, Hashable, Sendable, CaseIterable { case skip, zero }

/// The countdown settings shared by a Slides countdown slide and a Kids countdown item (same keys, same meaning).
/// Old Kids items have only `title` + `seconds`; every newer field is optional and needs TV app 1.4.0+.
public struct CountdownSettings: Hashable, Sendable {
    public var title: String?
    public var mode: CountdownMode?
    public var seconds: Int?
    /// 'HH:MM', 24 h, site time zone (until mode).
    public var until: String?
    public var audio: CountdownAudio?
    /// A missing value means 'next' (how old Kids items always behaved). New countdowns are saved with 'hold'.
    public var atZero: CountdownAtZero?
    /// Until mode when the time has passed: 'zero' (default for new items) or 'skip'.
    public var ifPassed: CountdownIfPassed?

    public static let needsAppNote = "Audio and countdown-to-a-time need Church TV OS app version 1.4.0 or newer on the TV."

    public init(title: String? = nil, mode: CountdownMode? = nil, seconds: Int? = nil, until: String? = nil,
                audio: CountdownAudio? = nil, atZero: CountdownAtZero? = nil, ifPassed: CountdownIfPassed? = nil) {
        self.title = title; self.mode = mode; self.seconds = seconds; self.until = until
        self.audio = audio; self.atZero = atZero; self.ifPassed = ifPassed
    }

    /// What the website creates for a new countdown.
    public static var new: CountdownSettings {
        CountdownSettings(title: "Service starts in", mode: .duration, seconds: 300, atZero: .hold, ifPassed: .zero)
    }

    /// Reads the countdown keys out of `object` (removing them, so the rest is the owner's `extra`).
    public init(consuming o: inout RawObject) {
        title = o.takeString("title")
        mode = o.takeEnum("mode")
        seconds = o.takeInt("seconds")
        until = o.takeString("until")
        audio = o.takeObject("audio").map(CountdownAudio.init(object:))
        atZero = o.takeEnum("at_zero")
        ifPassed = o.takeEnum("if_passed")
    }

    /// Writes the countdown keys into `o`.
    public func write(into o: inout RawObject) {
        o.put("title", title); o.put("mode", mode); o.put("seconds", seconds); o.put("until", until)
        if let audio { o["audio"] = .object(audio.object) }
        o.put("at_zero", atZero); o.put("if_passed", ifPassed)
    }

    public var effectiveMode: CountdownMode { mode ?? .duration }
    public var effectiveSeconds: Int { seconds ?? 0 }
    public var effectiveAtZero: CountdownAtZero { atZero ?? .next }
    public var effectiveIfPassed: CountdownIfPassed { ifPassed ?? .zero }

    /// Switching the mode fills the field the new mode needs (same as the website's selector).
    public mutating func setMode(_ new: CountdownMode) {
        mode = new
        if new == .until, (until ?? "").isEmpty { until = "09:00" }
        if new == .duration, effectiveSeconds <= 0 { seconds = 300 }
    }

    /// Chooses a library track with the website's defaults, keeping settings of a previous track.
    public mutating func setAudio(mediaId: String, url: String) {
        var a = audio ?? CountdownAudio(mediaId: mediaId, url: url)
        a.mediaId = mediaId; a.url = url
        audio = a
    }

    /// What is wrong with the settings, or nil (`countdownProblem` in render.ts).
    public var problem: String? {
        if effectiveMode == .until {
            if !CountdownSettings.isClock(until ?? "") { return "choose the clock time to count down to." }
        } else if effectiveSeconds <= 0 { return "the countdown needs at least 1 second." }
        if let audio, audio.url.isEmpty { return "choose an audio file, or remove the audio." }
        return nil
    }

    /// 'HH:MM' with a valid hour and minute.
    public static func isClock(_ s: String) -> Bool {
        let p = s.split(separator: ":", omittingEmptySubsequences: false)
        guard p.count == 2, p[0].count == 2, p[1].count == 2, let h = Int(p[0]), let m = Int(p[1]) else { return false }
        return (0...23).contains(h) && (0...59).contains(m)
    }
}

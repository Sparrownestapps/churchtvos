import Foundation

/// A JSON value for the free-form `payload` argument of `send_screen_command`.
public enum JSONValue: Encodable, Equatable, Sendable {
    case string(String), int(Int), bool(Bool)

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .int(let i): try c.encode(i)
        case .bool(let b): try c.encode(b)
        }
    }
}

/// The remote commands the database accepts (check constraint on screen_commands.command).
public enum RemoteCommand: Equatable, Sendable {
    case next
    case previous
    case jump(index: Int)
    /// `on == nil` toggles on the TV.
    case blank(on: Bool?)
    case stop
    case start(kind: PlayNowItem.Kind, id: UUID, minutes: Int)
    case message(text: String, seconds: Int, background: String?)
    case clearMessage

    /// Value of the `p_command` argument.
    public var name: String {
        switch self {
        case .next: return "next"
        case .previous: return "previous"
        case .jump: return "jump"
        case .blank: return "blank"
        case .stop: return "stop"
        case .start: return "start"
        case .message: return "message"
        case .clearMessage: return "clear_message"
        }
    }

    /// Value of the `p_payload` argument. Keys match what the SQL function and the TV read:
    /// jump {index}, blank {on}, start {kind,id,minutes}, message {text,seconds,background}.
    public var payload: [String: JSONValue] {
        switch self {
        case .next, .previous, .stop, .clearMessage:
            return [:]
        case .jump(let index):
            return ["index": .int(max(0, index))]
        case .blank(let on):
            return on.map { ["on": .bool($0)] } ?? [:]
        case .start(let kind, let id, let minutes):
            // The server clamps to 5...1440 minutes; clamp here too so the UI shows the truth.
            return ["kind": .string(kind.rawValue), "id": .string(id.uuidString.lowercased()),
                    "minutes": .int(min(1440, max(5, minutes)))]
        case .message(let text, let seconds, let background):
            var p: [String: JSONValue] = [
                "text": .string(text.trimmingCharacters(in: .whitespacesAndNewlines)),
                "seconds": .int(min(300, max(5, seconds))),
            ]
            if let background, !background.isEmpty { p["background"] = .string(background) }
            return p
        }
    }

    /// Client-side validation mirroring the server rules, so people get a message before a round trip.
    public var validationError: String? {
        if case .message(let text, _, _) = self {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return "Type a message first." }
            if t.count > 200 { return "A message can be up to 200 characters." }
        }
        return nil
    }
}

/// Parameters object for `rpc("send_screen_command", params:)`.
public struct SendCommandParams: Encodable, Equatable, Sendable {
    public let pScreenId: String
    public let pCommand: String
    public let pPayload: [String: JSONValue]

    public init(screenId: UUID, command: RemoteCommand) {
        pScreenId = screenId.uuidString.lowercased()
        pCommand = command.name
        pPayload = command.payload
    }

    enum CodingKeys: String, CodingKey { case pScreenId = "p_screen_id", pCommand = "p_command", pPayload = "p_payload" }
}

/// Message presets for "Send a message".
public enum MessagePreset: String, CaseIterable, Identifiable, Sendable {
    case startingSoon, welcome, pleaseSilence, parentsCheckIn, serviceEnding
    public var id: String { rawValue }
    public var text: String {
        switch self {
        case .startingSoon: return "Service starts in 5 minutes"
        case .welcome: return "Welcome! We are glad you are here."
        case .pleaseSilence: return "Please silence your phone"
        case .parentsCheckIn: return "Parents: please check in at the kids desk"
        case .serviceEnding: return "Service is ending, please collect your children"
        }
    }
    public var shortName: String {
        switch self {
        case .startingSoon: return "Starting soon"
        case .welcome: return "Welcome"
        case .pleaseSilence: return "Silence phones"
        case .parentsCheckIn: return "Parents"
        case .serviceEnding: return "Ending"
        }
    }
}

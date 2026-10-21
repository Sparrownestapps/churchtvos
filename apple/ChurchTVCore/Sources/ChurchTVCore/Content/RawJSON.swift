import Foundation

// MARK: - RawJSON

/// A complete JSON value. The content models (playlist items, deck slides, backgrounds, theme config) keep every key they do not
/// understand as `RawJSON` so the phone never destroys data written by the website or a newer TV app.
///
/// IMPORTANT: decode content with `ContentJSON.decoder()`, NOT `ChurchJSON.decoder()`. The latter converts snake_case keys to
/// camelCase, and that conversion also applies to the keys of free-form objects (it would turn `media_id` into `mediaId`).
public enum RawJSON: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([RawJSON])
    case object([String: RawJSON])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([RawJSON].self) { self = .array(a) }
        else { self = .object(try c.decode([String: RawJSON].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n):
            // Whole numbers are written as integers (30, not 30.0) exactly like JavaScript's JSON.stringify.
            if n == n.rounded(), abs(n) < 9e15 { try c.encode(Int64(n)) } else { try c.encode(n) }
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    public var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    public var doubleValue: Double? { if case .number(let n) = self { return n }; return nil }
    public var intValue: Int? { if case .number(let n) = self, n == n.rounded(), abs(n) < 9e15 { return Int(n) }; return nil }
    public var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    public var arrayValue: [RawJSON]? { if case .array(let a) = self { return a }; return nil }
    public var objectValue: [String: RawJSON]? { if case .object(let o) = self { return o }; return nil }
    public var isNull: Bool { if case .null = self { return true }; return false }

    public subscript(key: String) -> RawJSON? { objectValue?[key] }

    /// Parses JSON text (handy in tests and previews).
    public static func parse(_ text: String) throws -> RawJSON {
        try JSONDecoder().decode(RawJSON.self, from: Data(text.utf8))
    }
}

public typealias RawObject = [String: RawJSON]

// MARK: - Reading and writing keys

/// "Take" helpers read a known key and REMOVE it from the dictionary, so what is left over is exactly what the typed model does not
/// understand (it travels along as `extra`). A key holding a value of an unexpected type is left in place (and the typed field is nil).
/// JSON `null` is consumed and gives nil.
public extension Dictionary where Key == String, Value == RawJSON {
    mutating func takeString(_ key: String) -> String? {
        switch self[key] {
        case .string(let s)?: removeValue(forKey: key); return s
        case .null?: removeValue(forKey: key); return nil
        default: return nil
        }
    }
    mutating func takeInt(_ key: String) -> Int? {
        switch self[key] {
        case .number(let n)? where n == n.rounded() && abs(n) < 9e15: removeValue(forKey: key); return Int(n)
        case .null?: removeValue(forKey: key); return nil
        default: return nil
        }
    }
    mutating func takeDouble(_ key: String) -> Double? {
        switch self[key] {
        case .number(let n)?: removeValue(forKey: key); return n
        case .null?: removeValue(forKey: key); return nil
        default: return nil
        }
    }
    mutating func takeBool(_ key: String) -> Bool? {
        switch self[key] {
        case .bool(let b)?: removeValue(forKey: key); return b
        case .null?: removeValue(forKey: key); return nil
        default: return nil
        }
    }
    mutating func takeObject(_ key: String) -> [String: RawJSON]? {
        switch self[key] {
        case .object(let o)?: removeValue(forKey: key); return o
        case .null?: removeValue(forKey: key); return nil
        default: return nil
        }
    }
    mutating func takeStringArray(_ key: String) -> [String]? {
        switch self[key] {
        case .array(let a)? where a.allSatisfy({ $0.stringValue != nil }): removeValue(forKey: key); return a.compactMap(\.stringValue)
        case .null?: removeValue(forKey: key); return nil
        default: return nil
        }
    }
    /// An enum stored as a string. A value that is not one of the known cases stays in the dictionary (nil is returned).
    mutating func takeEnum<E: RawRepresentable>(_ key: String, as type: E.Type = E.self) -> E? where E.RawValue == String {
        switch self[key] {
        case .string(let s)? where E(rawValue: s) != nil: removeValue(forKey: key); return E(rawValue: s)
        case .null?: removeValue(forKey: key); return nil
        default: return nil
        }
    }

    /// Writes a value. A nil value writes nothing: the key was already taken out of the dictionary when the model was read, so an
    /// absent key stays absent (and a wrong-typed value the model could not read is left untouched).
    mutating func put(_ key: String, _ value: String?) { if let v = value { self[key] = .string(v) } }
    mutating func put(_ key: String, _ value: Int?) { if let v = value { self[key] = .number(Double(v)) } }
    mutating func put(_ key: String, _ value: Double?) { if let v = value { self[key] = .number(v) } }
    mutating func put(_ key: String, _ value: Bool?) { if let v = value { self[key] = .bool(v) } }
    mutating func put(_ key: String, _ value: [String]?) { if let v = value { self[key] = .array(v.map(RawJSON.string)) } }
    mutating func put(_ key: String, object value: [String: RawJSON]?) { if let v = value { self[key] = .object(v) } }
    mutating func put<E: RawRepresentable>(_ key: String, _ value: E?) where E.RawValue == String { if let v = value { self[key] = .string(v.rawValue) } }

    /// Writes a value, or an explicit JSON null when nil (the website writes `seconds: null` for "wait for Next").
    mutating func putNullable(_ key: String, _ value: String?) { self[key] = value.map(RawJSON.string) ?? .null }
    mutating func putNullable(_ key: String, _ value: Int?) { self[key] = value.map { .number(Double($0)) } ?? .null }
}

// MARK: - Codable bridge

/// A model that reads itself from, and writes itself to, a JSON object. Codable comes for free and encodes the object verbatim.
public protocol RawObjectCodable: Codable {
    init(object: [String: RawJSON])
    var object: [String: RawJSON] { get }
}

public extension RawObjectCodable {
    init(from decoder: Decoder) throws {
        let raw = try RawJSON(from: decoder)
        guard case .object(let o) = raw else {
            throw DecodingError.typeMismatch([String: RawJSON].self, .init(codingPath: decoder.codingPath, debugDescription: "Expected a JSON object"))
        }
        self.init(object: o)
    }
    func encode(to encoder: Encoder) throws { try RawJSON.object(object).encode(to: encoder) }
}

// MARK: - Coders for content rows

/// Coders for the content tables (playlists, signage_playlists, decks, slide_themes, songs, media).
/// No key strategy: the row models spell their snake_case keys out, and JSON columns keep their keys exactly as stored.
public enum ContentJSON {
    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = ChurchJSON.parseTimestamp(s) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unrecognised date \(s)")
        }
        return d
    }

    public static func encoder(pretty: Bool = false) -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = pretty ? [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(ChurchJSON.formatTimestamp(date))
        }
        return e
    }
}

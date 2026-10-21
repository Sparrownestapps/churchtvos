import Foundation
import Supabase

/// The parts of `organizations.branding` the content editors need (church colours, logos, YouTube channel for "Live now" items).
/// Decoded from the JSON column with `ContentJSON` rules (keys are snake_case). Unknown keys are ignored: the phone never writes branding.
public struct OrgBranding: Hashable, Sendable {
    public var primaryColor: String?
    public var accentColor: String?
    public var logoURL: String?
    public var logoDarkURL: String?
    public var youtubeChannelId: String?

    public init(primaryColor: String? = nil, accentColor: String? = nil, logoURL: String? = nil, logoDarkURL: String? = nil, youtubeChannelId: String? = nil) {
        self.primaryColor = primaryColor; self.accentColor = accentColor; self.logoURL = logoURL
        self.logoDarkURL = logoDarkURL; self.youtubeChannelId = youtubeChannelId
    }

    public init(json: RawJSON?) {
        func s(_ key: String) -> String? {
            guard let v = json?[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
            return v
        }
        primaryColor = ColorTools.isHex(s("primary_color")) ? s("primary_color")?.lowercased() : nil
        accentColor = ColorTools.isHex(s("accent_color")) ? s("accent_color")?.lowercased() : nil
        logoURL = s("logo_url"); logoDarkURL = s("logo_dark_url"); youtubeChannelId = s("youtube_channel_id")
    }

    /// The logo a sign with this background should show (dark logo on dark backgrounds), like SignItem.tsx.
    public func logo(forBackground hex: String) -> String? {
        ColorTools.luminance(hex) > 0.5 ? (logoURL ?? logoDarkURL) : (logoDarkURL ?? logoURL)
    }

    /// Sample branding for demo mode.
    public static let demo = OrgBranding(primaryColor: "#1f3a5f", accentColor: "#f59e0b", youtubeChannelId: "UCdemoChannel0000000000")
}

extension SupabaseService {
    /// Reads the church's branding (read-only). Throws a readable error.
    public func organizationBranding(organizationId: UUID) async throws -> OrgBranding {
        try await guarded {
            let response = try await client.from("organizations").select("branding").eq("id", value: organizationId.uuidString.lowercased()).limit(1).execute()
            guard let rows = try? JSONDecoder().decode([RawJSON].self, from: response.data) else { return OrgBranding() }
            return OrgBranding(json: rows.first?["branding"])
        }
    }
}

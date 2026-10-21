import Foundation

/// The only place with back-end settings. Both values are public by design (the publishable key
/// is protected by row-level security in the database); never put a secret/service key here.
public enum Config {
    public static let supabaseURL = URL(string: "https://gqkefjngblgomuovaivj.supabase.co")!
    public static let supabasePublishableKey = "sb_publishable_NdKbJRGxQykmJuV9OTLdXg_qkKSwlQy"

    public static let websiteURL = URL(string: "https://app.churchtvos.com")!
    public static let deleteAccountURL = URL(string: "https://app.churchtvos.com/delete-account.html")!
    public static let privacyURL = URL(string: "https://app.churchtvos.com/privacy.html")!
    public static let termsURL = URL(string: "https://app.churchtvos.com/terms.html")!

    /// The TV app must be at least this version to understand remote commands.
    public static let minimumRemoteTVVersion = "1.5.0"
    /// A TV is online when it checked in within this many seconds.
    public static let onlineWindow: TimeInterval = 90
    /// A status row older than this is shown as "stale".
    public static let statusStaleAfter: TimeInterval = 60
    /// Uploads larger than this show a warning (bytes).
    public static let largeUploadWarningBytes: Int64 = 200 * 1024 * 1024
    /// Storage bucket for media.
    public static let mediaBucket = "media"
}

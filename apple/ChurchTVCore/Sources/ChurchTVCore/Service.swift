import Foundation

public struct SessionUser: Equatable, Sendable {
    public let id: UUID
    public let email: String
    public init(id: UUID, email: String) { self.id = id; self.email = email }
}

/// A file picked from the camera roll, ready to upload.
public struct MediaUploadRequest: Sendable {
    public var organizationId: UUID
    public var module: AppModule
    public var folderId: UUID?
    public var fileURL: URL
    public var filename: String
    public var title: String
    public var kind: MediaKind
    public var sizeBytes: Int64
    public var contentType: String

    public init(organizationId: UUID, module: AppModule, folderId: UUID?, fileURL: URL, filename: String, title: String,
                kind: MediaKind, sizeBytes: Int64, contentType: String) {
        self.organizationId = organizationId; self.module = module; self.folderId = folderId; self.fileURL = fileURL
        self.filename = filename; self.title = title; self.kind = kind; self.sizeBytes = sizeBytes; self.contentType = contentType
    }
}

/// Everything the apps need from the back end. `SupabaseService` talks to the real project; `MockService` powers demo mode.
public protocol ChurchService: ContentService {
    var isDemo: Bool { get }

    // Session
    func restoreSession() async -> SessionUser?
    func signIn(email: String, password: String) async throws -> SessionUser
    func signOut() async

    // Churches
    func loadChurches() async throws -> [ChurchAccess]

    // Screens and status
    func listScreens(organizationId: UUID) async throws -> [ScreenInfo]
    func fetchStatuses(organizationId: UUID) async throws -> [UUID: ScreenStatus]

    // Remote control
    func send(_ command: RemoteCommand, to screenId: UUID) async throws

    // Content
    func playNowItems(organizationId: UUID, modules: [AppModule]) async throws -> [PlayNowItem]
    func schedule(organizationId: UUID, screens: [ScreenInfo], modules: [AppModule], now: Date) async throws -> [ScheduleEntry]

    // Media upload
    func mediaFolders(organizationId: UUID, module: AppModule) async throws -> [MediaFolder]
    func uploadMedia(_ request: MediaUploadRequest, progress: @escaping @Sendable (Double) -> Void) async throws

    // Push notifications
    func registerPushToken(_ token: String, environment: PushEnvironment) async throws
    func removePushToken(_ token: String) async throws
    func offlineAlertsEnabled(organizationId: UUID) async throws -> Bool
    func setOfflineAlerts(organizationId: UUID, enabled: Bool) async throws
}

public enum PushEnvironment: String, Sendable {
    case sandbox, production
}

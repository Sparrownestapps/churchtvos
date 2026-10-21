import Foundation

/// Native operations for the Mac app: screens (pair, edit, unpair), people, church settings and branding.
/// `SupabaseService` talks to the real tables and functions the website uses; `MockService` keeps demo state in memory.
/// Defaults throw "not available" so other conformers keep compiling. Server refusals pass through as readable `ChurchError`s.
public protocol OperationsService: Sendable {
    /// `rpc('is_platform_admin')`.
    func isPlatformAdmin() async throws -> Bool
    /// The `modules` registry. `availableOnly` hides modules that are not released.
    func listModules(availableOnly: Bool) async throws -> [ModuleDef]

    // Screens
    func loadScreenSettings(organizationId: UUID) async throws -> [UUID: ScreenSettings]
    func updateScreen(_ settings: ScreenSettings) async throws
    /// `rpc('claim_screen')`: pairs the TV showing `code` at a location. Refused above the plan's TV limit.
    func claimScreen(code: String, locationId: UUID, name: String?) async throws
    /// `rpc('release_screen')`: the TV forgets the church and shows a new code.
    func releaseScreen(id: UUID) async throws
    /// `rpc('tv_limit')`; nil when the server did not answer.
    func tvLimit(organizationId: UUID) async throws -> Int?
    /// Applies demo-mode edits to a list freshly read from the service (real services return the list unchanged).
    func overlayScreens(_ screens: [ScreenInfo]) async -> [ScreenInfo]

    // People
    func listMembers(organizationId: UUID) async throws -> [Member]
    func inviteMember(organizationId: UUID, draft: AccessDraft) async throws
    func updateMember(id: UUID, draft: AccessDraft) async throws
    func removeMember(id: UUID, organizationId: UUID) async throws

    // Church settings and branding
    func loadOrganization(id: UUID) async throws -> OrganizationSettings
    func saveOrganization(id: UUID, name: String, branding: BrandingSettings) async throws
    /// Uploads a logo image to `media/<org>/branding/...` and returns its public URL.
    func uploadBrandingLogo(organizationId: UUID, fileURL: URL, contentType: String) async throws -> String
    func loadPlan(organizationId: UUID) async throws -> [PlanRow]
}

public extension OperationsService {
    private var unavailable: ChurchError { ChurchError("This is not available here.") }
    func isPlatformAdmin() async throws -> Bool { false }
    func listModules(availableOnly: Bool) async throws -> [ModuleDef] { throw unavailable }
    func loadScreenSettings(organizationId: UUID) async throws -> [UUID: ScreenSettings] { throw unavailable }
    func updateScreen(_ settings: ScreenSettings) async throws { throw unavailable }
    func claimScreen(code: String, locationId: UUID, name: String?) async throws { throw unavailable }
    func releaseScreen(id: UUID) async throws { throw unavailable }
    func tvLimit(organizationId: UUID) async throws -> Int? { nil }
    func overlayScreens(_ screens: [ScreenInfo]) async -> [ScreenInfo] { screens }
    func listMembers(organizationId: UUID) async throws -> [Member] { throw unavailable }
    func inviteMember(organizationId: UUID, draft: AccessDraft) async throws { throw unavailable }
    func updateMember(id: UUID, draft: AccessDraft) async throws { throw unavailable }
    func removeMember(id: UUID, organizationId: UUID) async throws { throw unavailable }
    func loadOrganization(id: UUID) async throws -> OrganizationSettings { throw unavailable }
    func saveOrganization(id: UUID, name: String, branding: BrandingSettings) async throws { throw unavailable }
    func uploadBrandingLogo(organizationId: UUID, fileURL: URL, contentType: String) async throws -> String { throw unavailable }
    func loadPlan(organizationId: UUID) async throws -> [PlanRow] { throw unavailable }
}

/// Media library and song library writes (the website's MediaPage, SongsPage, SongEditor and SongImport).
public protocol LibraryService: Sendable {
    // Media
    /// Names of the playlists that use each file (`rpc('media_usage')`); the delete protection refuses these files.
    func mediaUsage(organizationId: UUID, module: AppModule) async throws -> [UUID: [String]]
    func renameMedia(id: UUID, organizationId: UUID, title: String) async throws
    /// Deletes the row first (the server refuses a file a playlist still uses) and only then the stored file.
    func deleteMedia(_ item: MediaItem, organizationId: UUID) async throws
    func moveMedia(ids: [UUID], organizationId: UUID, module: AppModule, to folder: UUID?) async throws
    func createFolder(organizationId: UUID, module: AppModule, parent: UUID?, siteId: UUID?, name: String) async throws -> MediaFolder
    func renameFolder(id: UUID, organizationId: UUID, name: String) async throws
    func moveFolder(id: UUID, organizationId: UUID, to parent: UUID?) async throws
    /// Files and sub-folders move up one level; nothing inside is deleted.
    func deleteFolder(id: UUID, organizationId: UUID) async throws

    // Songs
    /// Playlists that use each song (`rpc('song_usage')`).
    func songUsage(organizationId: UUID) async throws -> [UUID: [String]]
    func saveSong(_ draft: SongDraft, organizationId: UUID) async throws -> Song
    func insertSongs(_ drafts: [SongDraft], organizationId: UUID) async throws
    func deleteSong(id: UUID, organizationId: UUID) async throws
}

public extension LibraryService {
    private var unavailable: ChurchError { ChurchError("Editing the library is not available here.") }
    func mediaUsage(organizationId: UUID, module: AppModule) async throws -> [UUID: [String]] { [:] }
    func renameMedia(id: UUID, organizationId: UUID, title: String) async throws { throw unavailable }
    func deleteMedia(_ item: MediaItem, organizationId: UUID) async throws { throw unavailable }
    func moveMedia(ids: [UUID], organizationId: UUID, module: AppModule, to folder: UUID?) async throws { throw unavailable }
    func createFolder(organizationId: UUID, module: AppModule, parent: UUID?, siteId: UUID?, name: String) async throws -> MediaFolder { throw unavailable }
    func renameFolder(id: UUID, organizationId: UUID, name: String) async throws { throw unavailable }
    func moveFolder(id: UUID, organizationId: UUID, to parent: UUID?) async throws { throw unavailable }
    func deleteFolder(id: UUID, organizationId: UUID) async throws { throw unavailable }
    func songUsage(organizationId: UUID) async throws -> [UUID: [String]] { [:] }
    func saveSong(_ draft: SongDraft, organizationId: UUID) async throws -> Song { throw unavailable }
    func insertSongs(_ drafts: [SongDraft], organizationId: UUID) async throws { throw unavailable }
    func deleteSong(id: UUID, organizationId: UUID) async throws { throw unavailable }
}

/// Platform administrator console (the website's `dashboard/src/admin`). Every call is refused by the server for anyone else.
public protocol AdminService: Sendable {
    func adminListOrganizations() async throws -> [AdminOrg]
    /// `rpc('admin_update_organization')`: status, reason, notes, reviewed and the experimental NDI switch. Only pass what changes.
    func adminUpdateOrganization(_ id: UUID, change: AdminOrgChange) async throws
    /// `entitlements.upsert(rows, onConflict: 'organization_id,module')`.
    func adminUpsertEntitlements(_ rows: [AdminEntitlementRow]) async throws
    func adminDeleteEntitlement(organizationId: UUID, module: String) async throws
    func adminListAudit(organizationId: UUID?, action: String?, page: Int, pageSize: Int) async throws -> [AuditEntry]
    /// People, screens of one church (read only in the console).
    func adminListMembers(organizationId: UUID) async throws -> [Member]
    func adminInviteMember(organizationId: UUID, email: String, role: Role, moduleIds: [String]) async throws
    func adminRemoveMember(id: UUID, organizationId: UUID) async throws
    func adminListScreens(organizationId: UUID) async throws -> [AdminScreenRow]
}

public extension AdminService {
    private var unavailable: ChurchError { ChurchError("The admin console is not available here.") }
    func adminListOrganizations() async throws -> [AdminOrg] { throw unavailable }
    func adminUpdateOrganization(_ id: UUID, change: AdminOrgChange) async throws { throw unavailable }
    func adminUpsertEntitlements(_ rows: [AdminEntitlementRow]) async throws { throw unavailable }
    func adminDeleteEntitlement(organizationId: UUID, module: String) async throws { throw unavailable }
    func adminListAudit(organizationId: UUID?, action: String?, page: Int, pageSize: Int) async throws -> [AuditEntry] { throw unavailable }
    func adminListMembers(organizationId: UUID) async throws -> [Member] { throw unavailable }
    func adminInviteMember(organizationId: UUID, email: String, role: Role, moduleIds: [String]) async throws { throw unavailable }
    func adminRemoveMember(id: UUID, organizationId: UUID) async throws { throw unavailable }
    func adminListScreens(organizationId: UUID) async throws -> [AdminScreenRow] { throw unavailable }
}

import Foundation

/// A row of `media`: a file in the church's library (image, video or audio). Decode with `ContentJSON.decoder()`.
public struct MediaItem: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var organizationId: UUID?
    /// nil = shared across all sites.
    public var siteId: UUID?
    /// 'kids', 'signage', 'slides' (the library the file lives in).
    public var module: String
    public var folderId: UUID?
    public var title: String
    public var kind: MediaKind
    public var storagePath: String?
    public var url: String
    public var sizeBytes: Int64?
    public var createdAt: Date?

    public init(id: UUID = UUID(), organizationId: UUID? = nil, siteId: UUID? = nil, module: String, folderId: UUID? = nil, title: String,
                kind: MediaKind, storagePath: String? = nil, url: String, sizeBytes: Int64? = nil, createdAt: Date? = nil) {
        self.id = id; self.organizationId = organizationId; self.siteId = siteId; self.module = module; self.folderId = folderId
        self.title = title; self.kind = kind; self.storagePath = storagePath; self.url = url; self.sizeBytes = sizeBytes; self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, module, title, kind, url
        case organizationId = "organization_id", siteId = "site_id", folderId = "folder_id", storagePath = "storage_path"
        case sizeBytes = "size_bytes", createdAt = "created_at"
    }

    public var appModule: AppModule? { AppModule(rawValue: module) }
    public var urlValue: URL? { URL(string: url) }
}

/// What a media picker asks for: files of some kinds, optionally within one library (module).
public struct MediaQuery: Hashable, Sendable {
    public var module: AppModule
    /// Empty = any kind.
    public var kinds: Set<MediaKind>
    public init(module: AppModule, kinds: Set<MediaKind> = []) { self.module = module; self.kinds = kinds }
}

/// The files and folders of one library (module), with the browsing rules the picker needs.
/// Folders form a tree (`parentId`); files sit in a folder or at the top level (`folderId == nil`).
public struct MediaLibrary: Hashable, Sendable {
    public var module: AppModule
    public var items: [MediaItem]
    public var folders: [MediaFolder]
    public init(module: AppModule, items: [MediaItem] = [], folders: [MediaFolder] = []) { self.module = module; self.items = items; self.folders = folders }

    public func subfolders(of parent: UUID?) -> [MediaFolder] {
        folders.filter { $0.parentId == parent }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func files(in folder: UUID?, kinds: Set<MediaKind> = []) -> [MediaItem] {
        items.filter { $0.folderId == folder && (kinds.isEmpty || kinds.contains($0.kind)) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Folder chain from the top level down to `folder` (empty for the top level). Guards against cycles.
    public func breadcrumb(to folder: UUID?) -> [MediaFolder] {
        var chain: [MediaFolder] = []
        var cur = folder
        var seen = Set<UUID>()
        while let id = cur, !seen.contains(id), let f = folders.first(where: { $0.id == id }) {
            seen.insert(id); chain.insert(f, at: 0); cur = f.parentId
        }
        return chain
    }

    /// Search across the whole library (every folder) by title; folders are matched by name too.
    public func search(_ text: String, kinds: Set<MediaKind> = []) -> (folders: [MediaFolder], files: [MediaItem]) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return ([], []) }
        let fs = folders.filter { $0.name.lowercased().contains(q) }
        let ms = items.filter { $0.title.lowercased().contains(q) && (kinds.isEmpty || kinds.contains($0.kind)) }
        return (fs.sorted { $0.name < $1.name }, ms.sorted { $0.title < $1.title })
    }

    public func item(id: String) -> MediaItem? { items.first { $0.id.uuidString.caseInsensitiveCompare(id) == .orderedSame } }

    /// How many files of `kinds` are inside a folder, counting subfolders.
    public func count(in folder: UUID, kinds: Set<MediaKind> = [], depth: Int = 0) -> Int {
        guard depth < 20 else { return 0 }
        return files(in: folder, kinds: kinds).count + subfolders(of: folder).reduce(0) { $0 + count(in: $1.id, kinds: kinds, depth: depth + 1) }
    }
}

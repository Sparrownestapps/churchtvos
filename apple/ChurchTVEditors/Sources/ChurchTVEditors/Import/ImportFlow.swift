import SwiftUI
import Observation
import UniformTypeIdentifiers
import ChurchTVCore

extension String {
    var trimmedText: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// What the import adds to: a Slides deck or a Kids playlist (the same two targets as the website's importer).
enum ImportTarget: Hashable {
    case deck
    case kids

    var isDeck: Bool { self == .deck }
    var mode: ImportMode { isDeck ? .deck : .kidsPlaylist }
    var module: AppModule { isDeck ? .slides : .kids }
    var noun: String { isDeck ? "deck" : "playlist" }
    var itemNoun: String { isDeck ? "slide" : "item" }
}

/// What the editor receives when the import finishes: the uploaded pages and where they go.
struct ImportResult {
    var pages: [ImportedPage]
    var seconds: Int?
    var placement: ImportPlacement
}

/// Per-row progress on the importing screen.
enum RowStatus: Equatable {
    case wait
    case busy(Double)
    case ok(String?)
    case fail(String)
    case skipped(String)
}

struct ImportOutcome {
    var added = 0
    var failures: [ImportFailure] = []
    /// Name of the deck or playlist that was created ("new" mode).
    var createdName: String?
    var folderName: String?
    var folderError: String?
    var libraryOnly: [String] = []
    var stopped = false
    var saveError: String?
}

/// Serialises every read of the opened file (CoreGraphics PDF documents are not thread safe) and keeps work off the main thread.
actor ImportWorker {
    let session: ImportSession
    init(session: ImportSession) { self.session = session }
    func thumbnail(_ e: ImportEntry) -> Data? { session.thumbnail(for: e) }
    func plan(_ e: ImportEntry, options: ImportPlanOptions) throws -> [ImportPart] { try session.plan(e, options: options) }
    func prepare(_ p: ImportPart, directory: URL, backgroundHex: String?) throws -> PreparedFile { try session.prepare(p, directory: directory, backgroundHex: backgroundHex) }
}

@MainActor
@Observable
final class ImportFlow {
    enum Phase { case choose, loading, preview, importing, finished }
    enum PlacementMode: Hashable { case append, after, new }

    let target: ImportTarget
    @ObservationIgnored unowned let content: ContentModel
    /// Slides or items the deck/playlist has now (for the position stepper).
    let existingCount: Int
    /// Scope of the open deck/playlist (nil = all sites): the media folder and a new deck get the same.
    let siteId: UUID?
    /// Adds the finished pages to the open deck or playlist.
    @ObservationIgnored let apply: (ImportResult) -> Void

    var phase: Phase = .choose
    var errorText: String?
    private(set) var session: ImportSession?
    var entries: [ImportEntry] = []
    var mediaEntries: [ImportMediaEntry] = []
    var seconds: Int?
    var withPictures = false
    var placementMode: PlacementMode = .append
    var after = 0
    var newName = ""
    var folderName = ""
    private(set) var thumbs: [UUID: Data] = [:]
    private(set) var statuses: [UUID: RowStatus] = [:]
    private(set) var progress = 0.0
    private(set) var stopping = false
    private(set) var outcome = ImportOutcome()

    @ObservationIgnored private var worker: ImportWorker?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var stopped = false
    @ObservationIgnored private var folderTask: Task<UUID?, Never>?
    @ObservationIgnored private var folderIssue: String?
    @ObservationIgnored private var folderUsed: String?
    @ObservationIgnored private let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("import-\(UUID().uuidString)", isDirectory: true)

    init(target: ImportTarget, content: ContentModel, existingCount: Int, siteId: UUID?, apply: @escaping (ImportResult) -> Void) {
        self.target = target; self.content = content; self.existingCount = existingCount; self.siteId = siteId; self.apply = apply
        seconds = ImportBuilder.defaultSeconds(forDeck: target.isDeck)
        after = existingCount
    }

    deinit { try? FileManager.default.removeItem(at: tempDir) }

    // MARK: Derived

    var kind: ImportKind { session?.kind ?? .pdf }
    var placement: ImportPlacement {
        switch placementMode {
        case .append: return .append
        case .after: return .after(after)
        case .new: return .newItem(name: newName)
        }
    }
    var includedCount: Int { entries.filter(\.included).count }
    var problem: String? { ImportBuilder.problem(entries: entries, placement: placement) }
    var hasMedia: Bool { !mediaEntries.isEmpty }
    var mediaOn: Set<String> { Set(mediaEntries.filter { $0.included && $0.disabledReason == nil }.map(\.media.path)) }
    var hasTextSlides: Bool { entries.contains { $0.style == .text } }
    var hasPicturesOnTextSlides: Bool { session?.slides.values.contains { $0.kind == .text && $0.pictures.contains(where: \.supported) } ?? false }

    // MARK: Choosing a file

    static var fileTypes: [UTType] {
        var t: [UTType] = [.pdf, .image]
        for ext in ["pptx", "ppsx", "pptm"] { if let u = UTType(filenameExtension: ext) { t.append(u) } }
        t.append(UTType(importedAs: "org.openxmlformats.presentationml.presentation", conformingTo: .data))
        return t
    }

    func load(urls: [URL]) {
        guard phase == .choose || phase == .preview else { return }
        errorText = nil
        phase = .loading
        let dir = tempDir
        task = Task {
            do {
                let opened = try await Task.detached(priority: .userInitiated) { () -> ImportSession in
                    let copies = try Self.copyIn(urls, to: dir)
                    return try ImportSession.open(urls: copies)
                }.value
                adopt(opened)
            } catch {
                errorText = Formatting.message(for: error)
                phase = .choose
            }
        }
    }

    /// Copies picked files into our own temporary folder (the picker's access ends soon, and big files are read again later).
    nonisolated private static func copyIn(_ urls: [URL], to dir: URL) throws -> [URL] {
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var out: [URL] = []
        for (i, url) in urls.enumerated() {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let sub = dir.appendingPathComponent("in-\(UUID().uuidString.prefix(6))-\(i)", isDirectory: true)
            try fm.createDirectory(at: sub, withIntermediateDirectories: true)
            let dest = sub.appendingPathComponent(url.lastPathComponent)
            do { try fm.copyItem(at: url, to: dest) } catch { throw ChurchError("\(url.lastPathComponent) could not be read: \(Formatting.message(for: error))") }
            out.append(dest)
        }
        return out
    }

    func adopt(_ s: ImportSession) {
        session = s
        worker = ImportWorker(session: s)
        entries = s.entries
        mediaEntries = s.mediaEntries
        thumbs = [:]
        newName = s.name
        folderName = s.name
        withPictures = false
        phase = .preview
    }

    // MARK: Preview list

    func thumbnail(for e: ImportEntry) async {
        guard thumbs[e.id] == nil, e.style != .text, let worker else { return }
        if let d = await worker.thumbnail(e) { thumbs[e.id] = d }
    }

    func text(for e: ImportEntry) -> ImportedText? { session?.text(for: e) }

    func toggle(_ e: ImportEntry) {
        guard let i = entries.firstIndex(where: { $0.id == e.id }), entries[i].enabled else { return }
        entries[i].included.toggle()
    }

    func setAll(_ on: Bool) {
        var left = ImportLimits.maxPages
        for i in entries.indices {
            let can = entries[i].enabled && on && left > 0 && !(entries[i].style == .picture && entries[i].warning != nil)
            entries[i].included = can
            if can { left -= 1 }
        }
    }

    enum Move { case up, down, top, bottom }
    func move(_ e: ImportEntry, _ move: Move) {
        guard let i = entries.firstIndex(where: { $0.id == e.id }) else { return }
        let to: Int
        switch move {
        case .up: to = max(0, i - 1)
        case .down: to = min(entries.count - 1, i + 1)
        case .top: to = 0
        case .bottom: to = entries.count - 1
        }
        guard to != i else { return }
        entries.insert(entries.remove(at: i), at: to)
    }

    func toggleMedia(_ m: ImportMediaEntry) {
        guard let i = mediaEntries.firstIndex(where: { $0.id == m.id }), mediaEntries[i].disabledReason == nil else { return }
        mediaEntries[i].included.toggle()
    }

    func reset() {
        task?.cancel()
        session = nil; worker = nil; entries = []; mediaEntries = []; thumbs = [:]; phase = .choose; errorText = nil
    }

    // MARK: Import

    /// Stop: running uploads finish, the rest are skipped, and what is done is kept and added.
    func stop() { stopped = true; stopping = true }

    func run() {
        guard phase == .preview, problem == nil, let worker, let session, let org = content.organizationId else { return }
        phase = .importing
        stopped = false; stopping = false
        outcome = ImportOutcome()
        progress = 0
        folderTask = nil; folderIssue = nil; folderUsed = nil
        let chosen = entries.filter(\.included)
        statuses = Dictionary(uniqueKeysWithValues: chosen.map { ($0.id, RowStatus.wait) })
        let plan = ImportPlanOptions(mode: target.mode, withPictures: withPictures && target.isDeck, mediaOn: mediaOn)
        let secs = seconds
        let place = placement
        let module = target.module
        let dir = tempDir.appendingPathComponent("out", isDirectory: true)
        let wantedFolder = folderName.trimmedText.isEmpty ? session.name : folderName.trimmedText
        task = Task {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let bg = await brandColor(needed: !target.isDeck && session.kind == .pptx)
            var results = [JobResult](repeating: JobResult(), count: chosen.count)
            var finished = 0
            await withTaskGroup(of: (Int, JobResult).self) { group in
                var next = 0
                func startNext() {
                    guard next < chosen.count else { return }
                    let i = next; next += 1
                    let entry = chosen[i]
                    group.addTask { @MainActor [self] in
                        (i, await runJob(entry, worker: worker, plan: plan, org: org, module: module, directory: dir, wantedFolder: wantedFolder, background: bg))
                    }
                }
                for _ in 0..<min(ImportLimits.uploadsInFlight, chosen.count) { startNext() }
                while let (i, r) = await group.next() {
                    results[i] = r
                    finished += 1
                    progress = Double(finished) / Double(max(1, chosen.count))
                    startNext()
                }
            }
            try? FileManager.default.removeItem(at: dir)
            var out = ImportOutcome()
            out.folderName = folderUsed
            out.folderError = folderIssue
            out.stopped = stopped
            out.failures = results.compactMap(\.failure)
            out.libraryOnly = results.flatMap(\.libraryOnly)
            let pages = results.flatMap(\.pages)
            // Put the pages into the deck or playlist (or a new one).
            if !pages.isEmpty {
                if case .newItem(let name) = place {
                    await createNew(name: name, pages: pages, seconds: secs, into: &out)
                } else {
                    apply(ImportResult(pages: pages, seconds: secs, placement: place))
                    out.added = pages.count
                }
            }
            outcome = out
            phase = .finished
            if out.added > 0 { Haptics.success() } else { Haptics.failure() }
        }
    }

    struct JobResult {
        var pages: [ImportedPage] = []
        var libraryOnly: [String] = []
        var failure: ImportFailure?
    }

    private func runJob(_ entry: ImportEntry, worker: ImportWorker, plan: ImportPlanOptions, org: UUID, module: AppModule, directory: URL,
                        wantedFolder: String, background: String?) async -> JobResult {
        var r = JobResult()
        if stopped { statuses[entry.id] = .skipped("Not imported"); return r }
        statuses[entry.id] = .busy(0)
        let label = "\(session?.kind.unit.capitalized ?? "Page") \(entry.number)"
        do {
            let parts = try await worker.plan(entry, options: plan)
            for (k, part) in parts.enumerated() {
                if stopped && k > 0 { break }
                let base = Double(k) / Double(max(1, parts.count)), span = 1 / Double(max(1, parts.count))
                if part.source == nil {
                    r.pages.append(ImportedPage(entryNumber: entry.number, text: part.text, notes: part.notes))
                    statuses[entry.id] = .busy(base + span)
                    continue
                }
                let file = try await worker.prepare(part, directory: directory, backgroundHex: background)
                let folder = await folderId(org: org, module: module, wanted: wantedFolder)
                let item = try await upload(file, org: org, module: module, folder: folder) { [weak self] p in self?.statuses[entry.id] = .busy(base + p * span) }
                if part.role == .libraryOnly { r.libraryOnly.append(item.title) }
                else { r.pages.append(ImportedPage(entryNumber: entry.number, media: item, notes: part.notes)) }
            }
            statuses[entry.id] = .ok(r.libraryOnly.isEmpty ? nil : "\(r.libraryOnly.joined(separator: ", ")) added to the media library")
        } catch {
            let msg = Formatting.message(for: error)
            statuses[entry.id] = .fail(msg)
            r.failure = ImportFailure(entryId: entry.id, label: label, reason: msg)
        }
        return r
    }

    private func upload(_ f: PreparedFile, org: UUID, module: AppModule, folder: UUID?, progress: @escaping @MainActor (Double) -> Void) async throws -> MediaItem {
        let req = MediaUploadRequest(organizationId: org, module: module, folderId: folder, fileURL: f.url, filename: f.filename, title: f.title,
                                     kind: f.kind, sizeBytes: f.size, contentType: f.contentType)
        defer { try? FileManager.default.removeItem(at: f.url) }
        let item = try await content.uploadMedia(req, progress: { p in Task { @MainActor in progress(p) } })
        guard let item else { throw ChurchError("The file was uploaded but the server did not return it. Refresh the Media library.") }
        return item
    }

    /// The folder is created once, when the first file is about to upload; a taken name gets " (2)", " (3)".
    private func folderId(org: UUID, module: AppModule, wanted: String) async -> UUID? {
        if let t = folderTask { return await t.value }
        let t = Task { @MainActor () -> UUID? in
            guard let library = content.service as? any LibraryService else { return nil }
            let taken = (await content.folders(for: module)).filter { $0.parentId == nil }.map(\.name)
            let name = ImportNaming.uniqueFolderName(wanted: wanted, taken: taken)
            do {
                let f = try await library.createFolder(organizationId: org, module: module, parent: nil, siteId: siteId, name: name)
                folderUsed = f.name
                return f.id
            } catch {
                folderIssue = Formatting.message(for: error)   // the files go to the top level of the library
                return nil
            }
        }
        folderTask = t
        return await t.value
    }

    private func brandColor(needed: Bool) async -> String? {
        guard needed else { return nil }
        var branding: OrgBranding?
        if content.isDemo { branding = .demo }
        else if let org = content.organizationId, let service = content.service as? SupabaseService { branding = try? await service.organizationBranding(organizationId: org) }
        return ColorTools.isHex(branding?.primaryColor) ? branding?.primaryColor : ImportLimits.kidsBackgroundDefault
    }

    private func createNew(name: String, pages: [ImportedPage], seconds: Int?, into out: inout ImportOutcome) async {
        do {
            switch target {
            case .deck:
                var d = content.newDeckDraft(name: name)
                d.siteId = siteId
                d.slides = ImportBuilder.deckSlides(pages: pages, seconds: seconds, existing: [])
                _ = try await content.save(d)
            case .kids:
                var d = content.newPlaylistDraft(name: name)
                d.siteId = siteId
                d.items = ImportBuilder.playlistItems(pages: pages, seconds: seconds)
                _ = try await content.save(d, kind: .kids)
            }
            out.added = pages.count
            out.createdName = name.trimmedText
        } catch {
            out.added = 0
            out.saveError = Formatting.message(for: error)
        }
    }
}

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ChurchTVCore

/// Pure helpers for the media library page (kept free of UI so they can be reasoned about and tested).
enum MediaUploadRules {
    /// image, video or audio by file type; nil for anything else.
    static func kind(for url: URL) -> MediaKind? {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return nil }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        return nil
    }

    static func contentType(for url: URL) -> String { UTType(filenameExtension: url.pathExtension.lowercased())?.preferredMIMEType ?? "application/octet-stream" }
    static func title(for url: URL) -> String { url.deletingPathExtension().lastPathComponent }
}

/// One file in the upload list.
struct UploadJob: Identifiable, Equatable {
    enum State: Equatable { case waiting, uploading, done, failed(String) }
    let id = UUID()
    let url: URL
    var progress: Double = 0
    var state: State = .waiting
    var isLarge: Bool
}

@MainActor
@Observable
final class MediaPageModel {
    var module: AppModule
    var library = MediaLibrary(module: .kids)
    var usage: [UUID: [String]] = [:]
    var folder: UUID?
    var search = ""
    var selection: Set<UUID> = []
    var loading = false
    var loadError: String?
    var jobs: [UploadJob] = []
    var uploading = false
    var notice: String?

    init(module: AppModule) { self.module = module }

    func load(_ app: MenuModel, force: Bool = false) async {
        guard let org = app.church?.id else { return }
        loading = true; defer { loading = false }
        do {
            async let items = app.service.listMedia(organizationId: org, module: module, kinds: [])
            async let folders = app.service.mediaFolders(organizationId: org, module: module)
            let lib = MediaLibrary(module: module, items: try await items, folders: try await folders)
            library = lib
            usage = (try? await app.library?.mediaUsage(organizationId: org, module: module)) ?? [:]
            if let f = folder, !lib.folders.contains(where: { $0.id == f }) { folder = nil }
            selection = selection.filter { id in lib.items.contains { $0.id == id } }
            loadError = nil
        } catch { loadError = Formatting.message(for: error) }
    }

    /// Uploads files one after the other. The SDK upload has no byte progress, so progress is stage based.
    func upload(_ urls: [URL], app: MenuModel) {
        guard let org = app.church?.id else { return }
        var skipped: [String] = []
        var new: [UploadJob] = []
        for u in urls {
            guard MediaUploadRules.kind(for: u) != nil else { skipped.append(u.lastPathComponent); continue }
            let size = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            new.append(UploadJob(url: u, isLarge: size > Config.largeUploadWarningBytes))
        }
        notice = skipped.isEmpty ? nil : "Only images, videos and audio can be added. Skipped: \(skipped.prefix(3).joined(separator: ", "))\(skipped.count > 3 ? "…" : "")"
        jobs += new
        guard !uploading else { return }
        uploading = true
        let module = module, folder = folder
        Task {
            while let i = jobs.firstIndex(where: { $0.state == .waiting }) {
                jobs[i].state = .uploading
                let job = jobs[i]
                let access = job.url.startAccessingSecurityScopedResource()
                defer { if access { job.url.stopAccessingSecurityScopedResource() } }
                let size = (try? job.url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                let request = MediaUploadRequest(organizationId: org, module: module, folderId: folder, fileURL: job.url, filename: job.url.lastPathComponent,
                                                 title: MediaUploadRules.title(for: job.url), kind: MediaUploadRules.kind(for: job.url) ?? .image,
                                                 sizeBytes: size, contentType: MediaUploadRules.contentType(for: job.url))
                do {
                    _ = try await app.service.uploadMediaItem(request) { p in
                        Task { @MainActor [weak self] in if let j = self?.jobs.firstIndex(where: { $0.id == job.id }) { self?.jobs[j].progress = p } }
                    }
                    if let j = jobs.firstIndex(where: { $0.id == job.id }) { jobs[j].state = .done; jobs[j].progress = 1 }
                } catch {
                    if let j = jobs.firstIndex(where: { $0.id == job.id }) { jobs[j].state = .failed(Formatting.message(for: error)) }
                }
            }
            uploading = false
            await load(app, force: true)
            try? await Task.sleep(for: .seconds(6))
            jobs.removeAll { $0.state == .done }
        }
    }
}

struct MediaSection: View {
    @Environment(MenuModel.self) private var app
    @State private var page: MediaPageModel
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var renameTarget: RenameTarget?
    @State private var renameText = ""
    @State private var moveTarget: MoveTarget?
    @State private var deleteTarget: DeleteTarget?
    @State private var errorAlert: ErrorAlert?
    @State private var dropTargeted = false

    enum RenameTarget: Identifiable { case file(MediaItem), folder(MediaFolder)
        var id: UUID { switch self { case .file(let f): return f.id; case .folder(let f): return f.id } }
        var current: String { switch self { case .file(let f): return f.title; case .folder(let f): return f.name } }
    }
    enum MoveTarget: Identifiable { case files([MediaItem]), folder(MediaFolder)
        var id: String { switch self { case .files(let f): return f.map(\.id.uuidString).joined(); case .folder(let f): return f.id.uuidString } }
    }
    enum DeleteTarget: Identifiable { case files([MediaItem]), folder(MediaFolder)
        var id: String { switch self { case .files(let f): return f.map(\.id.uuidString).joined(); case .folder(let f): return f.id.uuidString } }
    }
    struct ErrorAlert: Identifiable { let id = UUID(); let title: String; let message: String }

    init() {
        let args = CommandLine.arguments
        let m = args.firstIndex(of: "-mediamodule").flatMap { $0 + 1 < args.count ? AppModule(rawValue: args[$0 + 1]) : nil } ?? .slides
        _page = State(initialValue: MediaPageModel(module: m))
    }

    private var church: ChurchAccess? { app.church }
    private var modules: [AppModule] { church?.modules ?? [] }
    private var lib: MediaLibrary { page.library }
    private func canEdit(_ item: MediaItem) -> Bool {
        guard let c = church else { return false }
        return ContentPermissions.canEditContent(role: c.role, modules: c.modules, siteIds: c.siteIds, module: page.module, siteId: item.siteId)
    }
    private var canAdd: Bool { church.map { ContentPermissions.canEditContent(role: $0.role, modules: $0.modules, module: page.module) } ?? false }

    private var visibleFolders: [MediaFolder] { page.search.isEmpty ? lib.subfolders(of: page.folder) : lib.search(page.search).folders }
    private var visibleFiles: [MediaItem] { page.search.isEmpty ? lib.files(in: page.folder) : lib.search(page.search).files }
    private var selected: [MediaItem] { lib.items.filter { page.selection.contains($0.id) } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ZStack {
                content
                if dropTargeted {
                    RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                        .background(Color.accentColor.opacity(0.08)).padding(8).overlay { Label("Drop files to add them to \(currentFolderName)", systemImage: "square.and.arrow.down").font(.title3) }.allowsHitTesting(false)
                }
            }
            if !page.jobs.isEmpty { uploadsPanel }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { newFolderName = ""; showNewFolder = true } label: { Label("New folder", systemImage: "folder.badge.plus") }.disabled(!canAdd).help("New folder here")
                Button { chooseFiles() } label: { Label("Add files", systemImage: "square.and.arrow.up") }.disabled(!canAdd).help("Add files (⌘U)").keyboardShortcut("u")
            }
        }
        .searchable(text: $page.search, prompt: "Search this library")
        .dropDestination(for: URL.self) { urls, _ in
            guard canAdd else { return false }
            page.upload(urls.filter { $0.isFileURL }, app: app); return true
        } isTargeted: { dropTargeted = $0 }
        .task(id: page.module) { await page.load(app) }
        .alert("New folder", isPresented: $showNewFolder) {
            TextField("Name", text: $newFolderName)
            Button("Create") { createFolder() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("In \(currentFolderName).") }
        .alert(renameTarget.map { "Rename “\($0.current)”" } ?? "", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") { rename() }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $moveTarget) { t in MoveFolderPicker(library: lib, target: t, onPick: { dest in moveTarget = nil; move(t, to: dest) }) }
        .confirmationDialog(deleteTitle, isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let t = deleteTarget { delete(t) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text(deleteMessage) }
        .alert(item: $errorAlert) { a in Alert(title: Text(a.title), message: Text(a.message), dismissButton: .default(Text("OK"))) }
    }

    // MARK: Header and content

    private var currentFolderName: String { page.folder.flatMap { id in lib.folders.first { $0.id == id }?.name } ?? "the top of the library" }

    private var header: some View {
        HStack(spacing: 12) {
            if modules.count > 1 {
                Picker("Library", selection: $page.module) { ForEach(modules) { Text($0.displayName).tag($0) } }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 260)
                    .onChange(of: page.module) { _, _ in page.folder = nil; page.selection = []; page.search = "" }
            } else { Text("\(page.module.displayName) media").font(.headline) }
            breadcrumb
            Spacer()
            Text(summary).font(.caption).foregroundStyle(.secondary)
            if !selected.isEmpty {
                Button("Move…") { moveTarget = .files(selected) }.disabled(!selected.allSatisfy(canEdit))
                Button("Delete \(selected.count)…", role: .destructive) { deleteTarget = .files(selected) }.disabled(!selected.allSatisfy(canEdit))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private var summary: String {
        let bytes = lib.items.reduce(Int64(0)) { $0 + ($1.sizeBytes ?? 0) }
        return "\(lib.items.count) file\(lib.items.count == 1 ? "" : "s"), \(Formatting.bytes(bytes))"
    }

    private var breadcrumb: some View {
        HStack(spacing: 4) {
            Button { page.folder = nil } label: { Label("Library", systemImage: "house") }.buttonStyle(.link)
                .dropDestination(for: String.self) { ids, _ in moveDropped(ids, to: nil) }
            ForEach(lib.breadcrumb(to: page.folder)) { f in
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                Button(f.name) { page.folder = f.id }.buttonStyle(.link)
                    .dropDestination(for: String.self) { ids, _ in moveDropped(ids, to: f.id) }
            }
        }
    }

    @ViewBuilder private var content: some View {
        if let e = page.loadError, lib.items.isEmpty {
            ContentUnavailableView("Couldn't load the library", systemImage: "exclamationmark.triangle", description: Text(e))
        } else if page.loading && lib.items.isEmpty && lib.folders.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visibleFolders.isEmpty && visibleFiles.isEmpty {
            ContentUnavailableView(page.search.isEmpty ? "Nothing here yet" : "No matches", systemImage: "photo.on.rectangle",
                                   description: Text(page.search.isEmpty ? (canAdd ? "Drag images, videos or audio from Finder into this window, or choose Add files." : "Editors can add files.") : "Nothing matches “\(page.search)”."))
        } else {
            ScrollView {
                if let n = page.notice { Text(n).font(.callout).foregroundStyle(.orange).padding(.horizontal, 14).padding(.top, 8).frame(maxWidth: .infinity, alignment: .leading) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 14)], spacing: 14) {
                    ForEach(visibleFolders) { f in FolderTile(folder: f, count: lib.count(in: f.id), canEdit: canAdd,
                                                                onOpen: { page.folder = f.id; page.search = "" },
                                                                onRename: { renameText = f.name; renameTarget = .folder(f) },
                                                                onMove: { moveTarget = .folder(f) }, onDelete: { deleteTarget = .folder(f) },
                                                                onDropIds: { moveDropped($0, to: f.id) }) }
                    ForEach(visibleFiles) { m in
                        FileTile(item: m, used: page.usage[m.id], selected: page.selection.contains(m.id), canEdit: canEdit(m))
                            .onTapGesture { toggle(m) }
                            .draggable("media:\(m.id.uuidString)")
                            .contextMenu {
                                Button("Rename…") { renameText = m.title; renameTarget = .file(m) }.disabled(!canEdit(m))
                                Button("Move to…") { moveTarget = .files(page.selection.contains(m.id) ? selected : [m]) }.disabled(!canEdit(m))
                                Divider()
                                Button("Delete…", role: .destructive) { deleteTarget = .files(page.selection.contains(m.id) ? selected : [m]) }.disabled(!canEdit(m))
                            }
                    }
                }
                .padding(14)
            }
            .contentShape(Rectangle()).onTapGesture { page.selection = [] }
            .refreshable { await page.load(app, force: true) }
        }
    }

    private func toggle(_ m: MediaItem) {
        if NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift) {
            if page.selection.contains(m.id) { page.selection.remove(m.id) } else { page.selection.insert(m.id) }
        } else { page.selection = page.selection == [m.id] ? [] : [m.id] }
    }

    private var uploadsPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            ForEach(page.jobs) { j in
                HStack(spacing: 10) {
                    Image(systemName: icon(j)).foregroundStyle(color(j))
                    Text(j.url.lastPathComponent).lineLimit(1)
                    if j.isLarge { Text("Large file").font(.caption).foregroundStyle(.orange) }
                    Spacer()
                    switch j.state {
                    case .uploading: ProgressView(value: j.progress).frame(width: 140)
                    case .waiting: Text("Waiting").font(.caption).foregroundStyle(.secondary)
                    case .done: Text("Added").font(.caption).foregroundStyle(.green)
                    case .failed(let m): Text(m).font(.caption).foregroundStyle(.red).lineLimit(2).help(m)
                    }
                    if case .failed = j.state { Button { page.jobs.removeAll { $0.id == j.id } } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
                }
            }
        }
        .padding(.horizontal, 14).padding(.bottom, 8).background(.bar)
    }

    private func icon(_ j: UploadJob) -> String { switch j.state { case .done: return "checkmark.circle.fill"; case .failed: return "exclamationmark.triangle.fill"; default: return "arrow.up.circle" } }
    private func color(_ j: UploadJob) -> Color { switch j.state { case .done: return .green; case .failed: return .red; default: return .accentColor } }

    // MARK: Actions

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image, .movie, .audio]
        panel.message = "Choose images, videos or audio to add to the \(page.module.displayName) library"
        if panel.runModal() == .OK { page.upload(panel.urls, app: app) }
    }

    private func run(_ title: String, _ work: @escaping () async throws -> Void) {
        Task {
            do { try await work(); await page.load(app, force: true) }
            catch { errorAlert = ErrorAlert(title: title, message: Formatting.message(for: error)) }
        }
    }

    private func createFolder() {
        guard let org = church?.id else { return }
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let parent = page.folder, module = page.module
        let site = parent.flatMap { id in lib.folders.first { $0.id == id }?.siteId }
        run("Couldn't create the folder") { _ = try await app.library?.createFolder(organizationId: org, module: module, parent: parent, siteId: site, name: name) }
    }

    private func rename() {
        guard let t = renameTarget, let org = church?.id else { return }
        let text = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        renameTarget = nil
        guard !text.isEmpty, text != t.current else { return }
        switch t {
        case .file(let f): run("Couldn't rename the file") { try await app.library?.renameMedia(id: f.id, organizationId: org, title: text) }
        case .folder(let f): run("Couldn't rename the folder") { try await app.library?.renameFolder(id: f.id, organizationId: org, name: text) }
        }
    }

    private func move(_ t: MoveTarget, to dest: UUID?) {
        guard let org = church?.id else { return }
        let module = page.module
        switch t {
        case .files(let files): run("Couldn't move the files") { try await app.library?.moveMedia(ids: files.map(\.id), organizationId: org, module: module, to: dest) }
        case .folder(let f): run("Couldn't move the folder") { try await app.library?.moveFolder(id: f.id, organizationId: org, to: dest) }
        }
    }

    /// An item was dragged onto a folder (or the breadcrumb).
    private func moveDropped(_ payloads: [String], to dest: UUID?) -> Bool {
        let ids = payloads.compactMap { $0.hasPrefix("media:") ? UUID(uuidString: String($0.dropFirst(6))) : nil }
        let files = lib.items.filter { ids.contains($0.id) && canEdit($0) && $0.folderId != dest }
        guard !files.isEmpty else { return false }
        move(.files(files), to: dest)
        return true
    }

    private var deleteTitle: String {
        switch deleteTarget {
        case .files(let f)?: return f.count == 1 ? "Delete “\(f[0].title)”?" : "Delete \(f.count) files?"
        case .folder(let f)?: return "Delete the folder “\(f.name)”?"
        case nil: return ""
        }
    }

    private var deleteMessage: String {
        switch deleteTarget {
        case .files(let f)?:
            let used = f.compactMap { m in page.usage[m.id].map { "“\(m.title)” is used in: \($0.joined(separator: ", "))." } }
            return (used.isEmpty ? "" : used.joined(separator: " ") + " The server will refuse to delete files that playlists still use.\n\n") + "This can't be undone."
        case .folder(let f)?:
            let parent = f.parentId.flatMap { id in lib.folders.first { $0.id == id }?.name }
            return "Nothing inside it is deleted: its files and sub-folders move up one level to \(parent.map { "“\($0)”" } ?? "the top of the library")."
        case nil: return ""
        }
    }

    private func delete(_ t: DeleteTarget) {
        guard let org = church?.id else { return }
        deleteTarget = nil
        Task {
            var failures: [String] = []
            switch t {
            case .files(let files):
                for f in files {
                    do { try await app.library?.deleteMedia(f, organizationId: org) } catch { failures.append(Formatting.message(for: error)) }
                }
                page.selection = []
            case .folder(let f):
                do { try await app.library?.deleteFolder(id: f.id, organizationId: org); if page.folder == f.id { page.folder = f.parentId } }
                catch { failures.append(Formatting.message(for: error)) }
            }
            await page.load(app, force: true)
            if !failures.isEmpty { errorAlert = ErrorAlert(title: failures.count == 1 ? "Can't delete" : "\(failures.count) couldn't be deleted", message: failures.prefix(5).joined(separator: "\n\n")) }
        }
    }
}

// MARK: - Tiles

private struct FolderTile: View {
    let folder: MediaFolder
    let count: Int
    let canEdit: Bool
    let onOpen: () -> Void
    let onRename: () -> Void
    let onMove: () -> Void
    let onDelete: () -> Void
    let onDropIds: ([String]) -> Bool
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "folder.fill").font(.system(size: 54)).foregroundStyle(.tint)
                .frame(maxWidth: .infinity, minHeight: 92)
                .background(RoundedRectangle(cornerRadius: 10).fill(targeted ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.08)))
            Text(folder.name).font(.callout.weight(.medium)).lineLimit(1)
            Text("\(count) file\(count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onOpen)
        .dropDestination(for: String.self) { ids, _ in onDropIds(ids) } isTargeted: { targeted = $0 }
        .contextMenu {
            Button("Open", action: onOpen)
            Button("Rename…", action: onRename).disabled(!canEdit)
            Button("Move to…", action: onMove).disabled(!canEdit)
            Divider()
            Button("Delete folder…", role: .destructive, action: onDelete).disabled(!canEdit)
        }
        .help("Double-click to open")
    }
}

private struct FileTile: View {
    let item: MediaItem
    let used: [String]?
    let selected: Bool
    let canEdit: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                MediaThumb(item: item).frame(height: 92).clipShape(RoundedRectangle(cornerRadius: 10))
                if let used, !used.isEmpty { Image(systemName: "link.circle.fill").foregroundStyle(.white, .orange).padding(5).help("Used in: \(used.joined(separator: ", "))") }
            }
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 3))
            Text(item.title).font(.callout).lineLimit(1)
            Text([item.kind.rawValue.capitalized, item.sizeBytes.map { Formatting.bytes($0) }].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .contentShape(Rectangle())
    }
}

/// Thumbnail: a real image, or an icon on a gradient for videos, audio and demo files.
struct MediaThumb: View {
    let item: MediaItem
    var body: some View {
        ZStack {
            if let demo = DemoMedia.parse(item.url) {
                LinearGradient(colors: [Color(hex: demo.color1), Color(hex: demo.color2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                overlayIcon(for: demo.kind, light: true)
            } else if item.kind == .image, let u = item.urlValue {
                Color.secondary.opacity(0.1)
                AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { ProgressView().controlSize(.small) }
            } else {
                Color.secondary.opacity(0.14)
                overlayIcon(for: item.kind, light: false)
            }
        }
        .clipped()
    }

    private func overlayIcon(for kind: MediaKind, light: Bool) -> some View {
        Image(systemName: kind == .video ? "play.circle.fill" : kind == .audio ? "waveform" : "photo").font(.system(size: kind == .image && light ? 0 : 30))
            .foregroundStyle(light ? .white.opacity(0.9) : .secondary)
    }
}

private struct MoveFolderPicker: View {
    @Environment(\.dismiss) private var dismiss
    let library: MediaLibrary
    let target: MediaSection.MoveTarget
    let onPick: (UUID?) -> Void

    private var excluded: Set<UUID> {
        guard case .folder(let f) = target else { return [] }
        var out: Set<UUID> = [f.id]
        var changed = true
        while changed { changed = false; for x in library.folders where x.parentId.map(out.contains) == true && !out.contains(x.id) { out.insert(x.id); changed = true } }
        return out
    }

    private func rows(_ parent: UUID?, depth: Int) -> [(MediaFolder, Int)] {
        library.subfolders(of: parent).filter { !excluded.contains($0.id) }.flatMap { [($0, depth)] + rows($0.id, depth: depth + 1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Move to…").font(.title3.weight(.semibold))
            List {
                Button { onPick(nil) } label: { Label("Top of the library", systemImage: "house") }.buttonStyle(.plain)
                ForEach(rows(nil, depth: 0), id: \.0.id) { f, depth in
                    Button { onPick(f.id) } label: { Label(f.name, systemImage: "folder").padding(.leading, CGFloat(depth) * 18) }.buttonStyle(.plain)
                }
            }
            .frame(minHeight: 240)
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(20).frame(width: 380, height: 380)
    }
}

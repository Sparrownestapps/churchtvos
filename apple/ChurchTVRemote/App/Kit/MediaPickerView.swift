import SwiftUI
import ChurchTVCore

/// Picks a file from one module's media library: folders with breadcrumbs, search across the whole library, a kind filter
/// (all, images, videos, audio) and thumbnails. "Add" opens the camera roll (and, for audio, the Files app) through the existing
/// `AddMediaView` upload flow, uploads into the folder you are looking at and then selects the new file for you.
///
/// Present it in a sheet. `onSelect` receives the chosen `MediaItem` and the picker dismisses itself:
/// ```swift
/// .sheet(isPresented: $picking) {
///     MediaPickerView(module: .slides, kinds: [.image, .video]) { item in clip.apply(item) }
/// }
/// ```
/// - `kinds`: what may be chosen (empty = anything). With a single kind the filter control is hidden.
/// - Adding is offered only to people who may add media (`model.canAddMedia`).
struct MediaPickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let module: AppModule
    var kinds: Set<MediaKind> = []
    var title = "Choose media"
    /// Id (text) of the file used now, marked in the list.
    var selectedId: String?
    var onSelect: (MediaItem) -> Void

    @State private var library: MediaLibrary?
    @State private var error: String?
    @State private var folder: UUID?
    @State private var search = ""
    @State private var filter: MediaKind?
    @State private var showAdd = false

    private var allowed: Set<MediaKind> { kinds.isEmpty ? [.image, .video, .audio] : kinds }
    /// The kinds shown right now: the user's filter within what is allowed.
    private var active: Set<MediaKind> { filter.map { [$0] } ?? allowed }

    var body: some View {
        NavigationStack {
            List {
                if let error { Section { Banner(text: error, style: .error) } }
                if library != nil {
                    if searching { searchResults } else { browser }
                } else if error == nil {
                    HStack { ProgressView(); Text("Loading library…").foregroundStyle(.secondary) }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search \(module.displayName) library")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if allowed.count > 1 { filterMenu }
                    if model.canAddMedia {
                        Button { showAdd = true } label: { Label("Add from camera roll", systemImage: "photo.badge.plus") }
                    }
                }
            }
            .task { await load(force: false) }
            .refreshable { await load(force: true) }
            .sheet(isPresented: $showAdd) {
                NavigationStack {
                    AddMediaView(embedded: false, fixedModule: module, initialFolder: folder, kinds: addKinds) { items in
                        showAdd = false
                        Task {
                            await load(force: true)
                            if let first = items.first, allowed.contains(first.kind) { onSelect(first); dismiss() }
                        }
                    }
                }
            }
        }
    }

    // MARK: Pieces

    private var searching: Bool { !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var addKinds: Set<MediaKind> {
        // The camera roll gives images and videos; audio comes from the Files app.
        var k: Set<MediaKind> = []
        if !allowed.isDisjoint(with: [.image, .video]) { k.insert(.image) }
        if allowed.contains(.audio) { k.insert(.audio) }
        return k
    }

    private var filterMenu: some View {
        Menu {
            Picker("Show", selection: $filter) {
                Text("All types").tag(MediaKind?.none)
                ForEach([MediaKind.image, .video, .audio].filter { allowed.contains($0) }, id: \.self) { Text($0.pluralLabel).tag(Optional($0)) }
            }
        } label: {
            Label(filter?.pluralLabel ?? "Filter", systemImage: filter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityLabel("Filter by type")
    }

    @ViewBuilder private var browser: some View {
        if let lib = library {
            Section {
                breadcrumb(lib)
            }
            let folders = lib.subfolders(of: folder)
            let files = lib.files(in: folder, kinds: active)
            if !folders.isEmpty {
                Section("Folders") {
                    ForEach(folders) { f in
                        Button { folder = f.id } label: {
                            HStack {
                                Image(systemName: "folder.fill").foregroundStyle(.tint).frame(width: 44)
                                Text(f.name).foregroundStyle(.primary)
                                Spacer()
                                Text("\(lib.count(in: f.id, kinds: active))").font(.footnote).foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                            }
                        }
                        .accessibilityLabel("Folder \(f.name), \(lib.count(in: f.id, kinds: active)) files")
                    }
                }
            }
            Section(files.isEmpty ? "" : "Files") {
                ForEach(files) { m in fileRow(m) }
                if files.isEmpty && folders.isEmpty {
                    Text(emptyText).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var emptyText: String {
        if folder != nil { return "Nothing here." }
        return "No \(active.count == 1 ? active.first!.pluralLabel.lowercased() : "files") in the \(module.displayName) library yet." + (model.canAddMedia ? " Use the add button to upload some." : "")
    }

    @ViewBuilder private var searchResults: some View {
        if let lib = library {
            let r = lib.search(search, kinds: active)
            if !r.folders.isEmpty {
                Section("Folders") {
                    ForEach(r.folders) { f in
                        Button { search = ""; folder = f.id } label: { Label(f.name, systemImage: "folder.fill").foregroundStyle(.primary) }
                    }
                }
            }
            Section(r.files.isEmpty ? "" : "Files") {
                ForEach(r.files) { m in fileRow(m, showFolder: true, lib: lib) }
                if r.files.isEmpty && r.folders.isEmpty { ContentUnavailableView.search(text: search).listRowBackground(Color.clear) }
            }
        }
    }

    private func breadcrumb(_ lib: MediaLibrary) -> some View {
        let chain = lib.breadcrumb(to: folder)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button { folder = nil } label: { Label("\(module.displayName) library", systemImage: "photo.stack") }
                    .disabled(chain.isEmpty)
                ForEach(chain) { f in
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary).accessibilityHidden(true)
                    Button(f.name) { folder = f.id }.disabled(f.id == folder)
                }
            }
            .font(.subheadline)
        }
        .accessibilityLabel("Folder path")
    }

    private func fileRow(_ m: MediaItem, showFolder: Bool = false, lib: MediaLibrary? = nil) -> some View {
        Button { onSelect(m); Haptics.selection(); dismiss() } label: {
            HStack(spacing: 12) {
                MediaThumbnail(url: m.url, kind: m.kind)
                    .frame(width: 64, height: 36).clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.title).foregroundStyle(.primary).lineLimit(2)
                    Text(detail(m, showFolder: showFolder, lib: lib)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if m.id.uuidString.lowercased() == selectedId?.lowercased() {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint).accessibilityLabel("Selected")
                }
            }
        }
        .accessibilityLabel("\(m.kind.label) \(m.title)")
    }

    private func detail(_ m: MediaItem, showFolder: Bool, lib: MediaLibrary?) -> String {
        var parts = [m.kind.label]
        if let size = m.sizeBytes { parts.append(Formatting.bytes(size)) }
        if showFolder, let lib, let f = m.folderId {
            let chain = lib.breadcrumb(to: f).map(\.name).joined(separator: " / ")
            if !chain.isEmpty { parts.append(chain) }
        }
        return parts.joined(separator: " · ")
    }

    private func load(force: Bool) async {
        do {
            library = try await model.content.mediaLibrary(module, force: force)
            error = nil
            if let f = folder, library?.folders.contains(where: { $0.id == f }) != true { folder = nil }
        } catch {
            if !(error is CancellationError) { self.error = Formatting.message(for: error) }
        }
    }
}

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import ChurchTVCore

/// A photo or video copied out of the photo picker into a temporary file, ready to upload.
struct PickedMedia: Identifiable {
    let id = UUID()
    let url: URL
    let filename: String
    let kind: MediaKind
    let size: Int64
    let contentType: String
}

/// Video files are copied (not loaded into memory) so large videos work.
struct MovieFile: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in SentTransferredFile(movie.url) } importing: { received in
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("uploads", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent("\(UUID().uuidString)-\(received.file.lastPathComponent)")
            try FileManager.default.copyItem(at: received.file, to: dest)
            return MovieFile(url: dest)
        }
    }
}

public struct AddMediaView: View {
    @Environment(ContentModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var embedded: Bool
    /// Media picker flow (see `MediaPickerView`): lock the library, start in a folder, allow audio files from the Files app, and
    /// get the new library rows back. All optional; the plain "Add media" screen uses none of them.
    var fixedModule: AppModule? = nil
    var initialFolder: UUID? = nil
    /// Kinds the caller wants. Empty = photos and videos (the normal screen). Contains `.audio` = also offer "Choose audio files".
    var kinds: Set<MediaKind> = []
    var onUploaded: (([MediaItem]) -> Void)? = nil

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var pickedPhotos: [PickedMedia] = []
    @State private var pickedAudio: [PickedMedia] = []
    @State private var importingAudio = false
    @State private var startedInFolder = false
    @State private var preparing = false
    @State private var module: AppModule?
    @State private var folders: [MediaFolder] = []
    @State private var folderId: UUID?
    @State private var uploading = false
    @State private var progress = 0.0
    @State private var currentIndex = 0
    @State private var message: String?
    @State private var errorText: String?
    @State private var confirmLarge = false
    @State private var uploadTask: Task<Void, Never>?

    public init(embedded: Bool, fixedModule: AppModule? = nil, initialFolder: UUID? = nil, kinds: Set<MediaKind> = [], onUploaded: (([MediaItem]) -> Void)? = nil) {
        self.embedded = embedded; self.fixedModule = fixedModule; self.initialFolder = initialFolder; self.kinds = kinds; self.onUploaded = onUploaded
    }

    private var picked: [PickedMedia] { pickedPhotos + pickedAudio }
    private var showsPhotos: Bool { kinds.isEmpty || kinds.contains(.image) || kinds.contains(.video) }
    private var showsAudio: Bool { kinds.contains(.audio) }
    private var modules: [AppModule] { fixedModule.map { [$0] } ?? model.church?.modules ?? [] }
    private var total: Int64 { picked.reduce(0) { $0 + $1.size } }
    private var hasLarge: Bool { picked.contains { $0.size > Config.largeUploadWarningBytes } }

    public var body: some View {
        Form {
            if !model.canAddMedia {
                Section { Banner(text: "Adding media needs the Editor role or above. Ask a church admin.", style: .warning) }
            }
            if model.isDemo { Section { Banner(text: "Demo mode: files are not really uploaded.", style: .info, systemImage: "sparkles") } }

            Section("Library") {
                if fixedModule != nil {
                    LabeledContent("Add to", value: module?.displayName ?? "")
                } else {
                    Picker("Add to", selection: $module) {
                        ForEach(modules) { Text($0.displayName).tag(Optional($0)) }
                    }
                }
                Picker("Folder", selection: $folderId) {
                    Text("No folder (top level)").tag(UUID?.none)
                    ForEach(folders.sorted { path($0) < path($1) }) { Text(path($0)).tag(Optional($0.id)) }
                }
            }

            Section(showsPhotos ? "Photos and videos" : "Audio") {
                if showsPhotos {
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 20, matching: .any(of: [.images, .videos])) {
                        Label(pickedPhotos.isEmpty ? "Choose photos or videos" : "Change selection", systemImage: "photo.on.rectangle.angled")
                    }
                    .disabled(uploading)
                }
                if showsAudio {
                    Button { importingAudio = true } label: { Label(pickedAudio.isEmpty ? "Choose audio files" : "Change audio files", systemImage: "music.note") }
                        .disabled(uploading)
                }
                if preparing { HStack { ProgressView(); Text("Preparing…").foregroundStyle(.secondary) } }
                ForEach(picked) { p in
                    HStack {
                        Image(systemName: p.kind == .video ? "video.fill" : p.kind == .audio ? "music.note" : "photo.fill").foregroundStyle(.tint).accessibilityHidden(true)
                        VStack(alignment: .leading) {
                            Text(p.filename).lineLimit(1)
                            Text(Formatting.bytes(p.size)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                if hasLarge {
                    Banner(text: "One or more videos are over 200 MB. Use Wi-Fi and keep the app open; large uploads can take a long time.", style: .warning)
                }
            }

            if uploading {
                Section("Uploading") {
                    ProgressView(value: min(1, (Double(currentIndex) + progress) / Double(max(1, picked.count))))
                    Text("File \(min(currentIndex + 1, picked.count)) of \(picked.count)").font(.footnote).foregroundStyle(.secondary)
                    Button("Cancel upload", role: .destructive) { uploadTask?.cancel() }
                }
            }
            if let m = message { Section { Banner(text: m, style: .info, systemImage: "checkmark.circle.fill") } }
            if let e = errorText { Section { Banner(text: e, style: .error) } }

            Section {
                Button { if hasLarge { confirmLarge = true } else { startUpload() } } label: {
                    Label("Upload \(picked.count) file\(picked.count == 1 ? "" : "s")" + (total > 0 ? " (\(Formatting.bytes(total)))" : ""), systemImage: "icloud.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .disabled(picked.isEmpty || uploading || module == nil || !model.canAddMedia)
            }
        }
        .navigationTitle("Add media")
        .inlineNavigationTitle()
        .toolbar { if !embedded { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.cancelShortcut() } } }
        .onAppear { if module == nil { module = fixedModule ?? modules.first } }
        .task(id: module) {
            folderId = (!startedInFolder && module == fixedModule) ? initialFolder : nil
            startedInFolder = true
            if let module { folders = await model.folders(for: module) }
            if folderId != nil, !folders.contains(where: { $0.id == folderId }) { folderId = nil }
        }
        .onChange(of: pickerItems) { _, items in Task { await prepare(items) } }
        .fileImporter(isPresented: $importingAudio, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): importAudio(urls)
            case .failure(let error): errorText = "Could not read the audio file: \(Formatting.message(for: error))"
            }
        }
        .confirmationDialog("Upload large files?", isPresented: $confirmLarge, titleVisibility: .visible) {
            Button("Upload anyway") { startUpload() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("A file is over 200 MB. This can use a lot of mobile data.") }
    }

    // MARK: Loading from the picker

    private func prepare(_ items: [PhotosPickerItem]) async {
        preparing = true; errorText = nil; message = nil
        defer { preparing = false }
        var result: [PickedMedia] = []
        for item in items {
            let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
            do {
                if isVideo {
                    if let movie = try await item.loadTransferable(type: MovieFile.self) {
                        let size = (try? FileManager.default.attributesOfItem(atPath: movie.url.path)[.size] as? Int64) ?? 0
                        let name = movie.url.lastPathComponent.split(separator: "-", maxSplits: 5).last.map(String.init) ?? movie.url.lastPathComponent
                        let type = UTType(filenameExtension: movie.url.pathExtension)?.preferredMIMEType ?? "video/quicktime"
                        result.append(PickedMedia(url: movie.url, filename: name, kind: .video, size: size, contentType: type))
                    }
                } else if let data = try await item.loadTransferable(type: Data.self), let jpeg = Self.jpeg(from: data) {
                    // HEIC photos become JPEG so every TV and browser can show them.
                    let name = "photo-\(UUID().uuidString.prefix(8)).jpg"
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                    try jpeg.write(to: url)
                    result.append(PickedMedia(url: url, filename: name, kind: .image, size: Int64(jpeg.count), contentType: "image/jpeg"))
                }
            } catch {
                errorText = "Could not read one of the files: \(Formatting.message(for: error))"
            }
        }
        pickedPhotos = result
    }

    /// Audio files come from the Files app. They are copied (not loaded into memory) so long tracks work.
    private func importAudio(_ urls: [URL]) {
        errorText = nil; message = nil
        var result: [PickedMedia] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("uploads", isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let dest = dir.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")
                try FileManager.default.copyItem(at: url, to: dest)
                let size = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int64) ?? 0
                let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "audio/mpeg"
                result.append(PickedMedia(url: dest, filename: url.lastPathComponent, kind: .audio, size: size, contentType: type))
            } catch {
                errorText = "Could not read \(url.lastPathComponent): \(Formatting.message(for: error))"
            }
        }
        pickedAudio = result
    }

    /// "Series / Week 1" for nested folders.
    private func path(_ f: MediaFolder) -> String {
        var names = [f.name]; var cur = f.parentId; var guardCount = 0
        while let id = cur, let p = folders.first(where: { $0.id == id }), guardCount < 20 { names.insert(p.name, at: 0); cur = p.parentId; guardCount += 1 }
        return names.joined(separator: " / ")
    }

    private static func jpeg(from data: Data) -> Data? {
        jpegData(fromImageData: data)
    }

    // MARK: Upload

    private func startUpload() {
        guard let org = model.church?.id, let module else { return }
        errorText = nil; message = nil; uploading = true; currentIndex = 0; progress = 0
        let files = picked
        let folder = folderId
        uploadTask = Task {
            var done = 0
            var added: [MediaItem] = []
            for (i, f) in files.enumerated() {
                if Task.isCancelled { break }
                currentIndex = i; progress = 0
                let title = (f.filename as NSString).deletingPathExtension
                let req = MediaUploadRequest(organizationId: org, module: module, folderId: folder, fileURL: f.url, filename: f.filename,
                                             title: title, kind: f.kind, sizeBytes: f.size, contentType: f.contentType)
                do {
                    if let item = try await model.uploadMedia(req, progress: { p in Task { @MainActor in progress = p } }) { added.append(item) }
                    done += 1
                    try? FileManager.default.removeItem(at: f.url)
                } catch {
                    errorText = "\(f.filename): \(Formatting.message(for: error))"
                    break
                }
            }
            uploading = false
            if done > 0 {
                message = "Added \(done) file\(done == 1 ? "" : "s") to \(module.displayName)."
                Haptics.success()
                pickedPhotos = []; pickedAudio = []; pickerItems = []
                if let onUploaded, !added.isEmpty { onUploaded(added) }
            } else if errorText != nil { Haptics.failure() }
        }
    }
}

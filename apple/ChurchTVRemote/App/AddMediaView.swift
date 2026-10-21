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

struct AddMediaView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var embedded: Bool

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var picked: [PickedMedia] = []
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

    private var modules: [AppModule] { model.church?.modules ?? [] }
    private var total: Int64 { picked.reduce(0) { $0 + $1.size } }
    private var hasLarge: Bool { picked.contains { $0.size > Config.largeUploadWarningBytes } }

    var body: some View {
        Form {
            if !model.canAddMedia {
                Section { Banner(text: "Adding media needs the Editor role or above. Ask a church admin.", style: .warning) }
            }
            if model.isDemo { Section { Banner(text: "Demo mode: files are not really uploaded.", style: .info, systemImage: "sparkles") } }

            Section("Library") {
                Picker("Add to", selection: $module) {
                    ForEach(modules) { Text($0.displayName).tag(Optional($0)) }
                }
                Picker("Folder", selection: $folderId) {
                    Text("No folder (top level)").tag(UUID?.none)
                    ForEach(folders) { Text($0.name).tag(Optional($0.id)) }
                }
            }

            Section("Photos and videos") {
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 20, matching: .any(of: [.images, .videos])) {
                    Label(picked.isEmpty ? "Choose photos or videos" : "Change selection", systemImage: "photo.on.rectangle.angled")
                }
                .disabled(uploading)
                if preparing { HStack { ProgressView(); Text("Preparing…").foregroundStyle(.secondary) } }
                ForEach(picked) { p in
                    HStack {
                        Image(systemName: p.kind == .video ? "video.fill" : "photo.fill").foregroundStyle(.tint).accessibilityHidden(true)
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if !embedded { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } } }
        .onAppear { if module == nil { module = modules.first } }
        .task(id: module) {
            folderId = nil
            if let module { folders = await model.folders(for: module) }
        }
        .onChange(of: pickerItems) { _, items in Task { await prepare(items) } }
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
        picked = result
    }

    private static func jpeg(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return image.jpegData(compressionQuality: 0.9)
    }

    // MARK: Upload

    private func startUpload() {
        guard let org = model.church?.id, let module else { return }
        errorText = nil; message = nil; uploading = true; currentIndex = 0; progress = 0
        let files = picked
        let folder = folderId
        uploadTask = Task {
            var done = 0
            for (i, f) in files.enumerated() {
                if Task.isCancelled { break }
                currentIndex = i; progress = 0
                let title = (f.filename as NSString).deletingPathExtension
                let req = MediaUploadRequest(organizationId: org, module: module, folderId: folder, fileURL: f.url, filename: f.filename,
                                             title: title, kind: f.kind, sizeBytes: f.size, contentType: f.contentType)
                do {
                    try await model.upload(req) { p in Task { @MainActor in progress = p } }
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
                picked = []; pickerItems = []
            } else if errorText != nil { Haptics.failure() }
        }
    }
}

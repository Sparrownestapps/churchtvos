import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ChurchTVCore

/// The song library: list, editor with sections and arrangement, live slide preview, and import of SongSelect (.usr), ChordPro and text files
/// (picked, dropped from Finder, or pasted). Parsers are the Swift port of the website's songParsers (Core `SongParsers`).
struct SongsSection: View {
    @Environment(MenuModel.self) private var app
    @State private var songs: [Song] = []
    @State private var usage: [UUID: [String]] = [:]
    @State private var loaded = false
    @State private var loadError: String?
    @State private var search = ""
    @State private var selection: UUID?
    @State private var editingNew = false
    @State private var importItems: [ImportEntry] = []
    @State private var showImport = false
    @State private var showPaste = false
    @State private var dropTargeted = false
    @State private var toDelete: Song?
    @State private var errorText: String?

    private var canEdit: Bool { app.church.map { ContentPermissions.canEditRole($0.role) } ?? false }
    private var filtered: [Song] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let list = songs.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return q.isEmpty ? list : list.filter { $0.title.lowercased().contains(q) || ($0.authors ?? "").lowercased().contains(q) || ($0.ccliNumber ?? "").contains(q) }
    }

    var body: some View {
        HSplitView {
            list.frame(minWidth: 280, idealWidth: 330, maxWidth: 440)
            detail.frame(minWidth: 460, maxWidth: .infinity)
        }
        .overlay { if dropTargeted { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8])).background(Color.accentColor.opacity(0.08)).padding(8).overlay { Label("Drop SongSelect, ChordPro or text files to import", systemImage: "square.and.arrow.down").font(.title3) }.allowsHitTesting(false) } }
        .dropDestination(for: URL.self) { urls, _ in
            guard canEdit else { return false }
            readFiles(urls.filter(\.isFileURL)); return true
        } isTargeted: { dropTargeted = $0 }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { selection = nil; editingNew = true } label: { Label("New song", systemImage: "plus") }.disabled(!canEdit).help("New song")
                Menu {
                    Button("From files…") { chooseFiles() }
                    Button("Paste lyrics…") { showPaste = true }
                } label: { Label("Import", systemImage: "square.and.arrow.down") }.disabled(!canEdit).help("Import songs")
            }
        }
        .sheet(isPresented: $showImport) { ImportSheet(entries: $importItems, library: songs) { await load() } }
        .sheet(isPresented: $showPaste) { PasteSheet { entry in importItems = [entry]; showPaste = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showImport = true } } }
        .confirmationDialog("Delete “\(toDelete?.title ?? "")”?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let s = toDelete { delete(s) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let s = toDelete, let used = usage[s.id] { Text("Used in: \(used.joined(separator: ", ")). The server will refuse to delete a song that playlists still use.") }
        }
        .alert("Couldn't finish", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorText ?? "") }
        .task { await load() }
    }

    private var list: some View {
        VStack(spacing: 0) {
            TextField("Search title, author or CCLI number", text: $search).textFieldStyle(.roundedBorder).padding(10)
            Divider()
            List(selection: Binding(get: { selection }, set: { selection = $0; editingNew = false })) {
                ForEach(filtered) { s in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.title).font(.body.weight(.medium)).lineLimit(1)
                        Text([s.authors, usage[s.id].map { "used in \($0.count)" }].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .tag(s.id)
                    .contextMenu {
                        Button("Duplicate") { duplicate(s) }.disabled(!canEdit)
                        Button("Delete…", role: .destructive) { toDelete = s }.disabled(!canEdit)
                    }
                }
            }
            .listStyle(.inset)
            .overlay {
                if !loaded { ProgressView() }
                else if let e = loadError { Text(e).foregroundStyle(.red).padding() }
                else if songs.isEmpty { Text("No songs yet. Add one, or drop SongSelect or text files here.").foregroundStyle(.secondary).multilineTextAlignment(.center).padding() }
            }
            Divider()
            Text("\(songs.count) song\(songs.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary).padding(8)
        }
    }

    @ViewBuilder private var detail: some View {
        if editingNew {
            SongEditor(draft: SongDraft(), isNew: true, canEdit: canEdit, onSaved: { s in editingNew = false; selection = s.id; await load() }, onDelete: nil).id("new")
        } else if let s = songs.first(where: { $0.id == selection }) {
            SongEditor(draft: SongDraft(s), isNew: false, canEdit: canEdit, onSaved: { _ in await load() }, onDelete: { toDelete = s }).id(s.id)
        } else {
            ContentUnavailableView("Choose a song", systemImage: "music.note.list", description: Text(canEdit ? "Edit lyrics, sections and the order they play in. Drag SongSelect (.usr), ChordPro or text files onto this window to import." : "Select a song to see its slides."))
        }
    }

    // MARK: Actions

    private func load() async {
        guard let org = app.church?.id else { return }
        do {
            songs = try await app.service.listSongs(organizationId: org)
            usage = (try? await app.library?.songUsage(organizationId: org)) ?? [:]
            loadError = nil
            if CommandLine.arguments.contains("-songpick"), selection == nil { selection = filtered.first?.id }
        } catch { loadError = Formatting.message(for: error) }
        loaded = true
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.allowedContentTypes = SongParsers.fileExtensions.compactMap { UTType(filenameExtension: $0) } + [.plainText]
        panel.message = "Choose SongSelect (.usr), ChordPro or text files"
        if panel.runModal() == .OK { readFiles(panel.urls) }
    }

    private func readFiles(_ urls: [URL]) {
        var entries: [ImportEntry] = []
        var skipped: [String] = []
        for u in urls {
            let access = u.startAccessingSecurityScopedResource()
            defer { if access { u.stopAccessingSecurityScopedResource() } }
            guard SongParsers.fileExtensions.contains(u.pathExtension.lowercased()), let data = try? Data(contentsOf: u) else { skipped.append(u.lastPathComponent); continue }
            let parsed = SongParsers.parseFile(name: u.lastPathComponent, text: SongParsers.decodeText(data))
            entries.append(ImportEntry(fileName: u.lastPathComponent, kind: parsed.kind, source: .file, song: parsed.song))
        }
        if !skipped.isEmpty { errorText = "Could not read: \(skipped.prefix(4).joined(separator: ", ")). Use .usr, .cho, .chordpro, .pro or .txt files." }
        guard !entries.isEmpty else { return }
        importItems = entries; showImport = true
    }

    private func duplicate(_ s: Song) {
        guard let org = app.church?.id else { return }
        Task {
            do { _ = try await app.library?.saveSong(SongDraft(s).duplicated(), organizationId: org); await load() }
            catch { errorText = Formatting.message(for: error) }
        }
    }

    private func delete(_ s: Song) {
        guard let org = app.church?.id else { return }
        toDelete = nil
        Task {
            do { try await app.library?.deleteSong(id: s.id, organizationId: org); if selection == s.id { selection = nil }; await load() }
            catch { errorText = Formatting.message(for: error) }
        }
    }
}

// MARK: - Editor

private struct SongEditor: View {
    @Environment(MenuModel.self) private var app
    @State var draft: SongDraft
    let isNew: Bool
    let canEdit: Bool
    let onSaved: (Song) async -> Void
    let onDelete: (() -> Void)?
    @State private var original: SongDraft
    @State private var saving = false
    @State private var error: String?
    @State private var saved = false

    init(draft: SongDraft, isNew: Bool, canEdit: Bool, onSaved: @escaping (Song) async -> Void, onDelete: (() -> Void)?) {
        _draft = State(initialValue: draft); _original = State(initialValue: draft); self.isNew = isNew; self.canEdit = canEdit; self.onSaved = onSaved; self.onDelete = onDelete
    }

    private var changed: Bool { draft != original }
    private var slides: [LyricSlide] { SongExpander.expand(sections: draft.sections, arrangement: draft.storedArrangement, linesPerSlide: draft.linesPerSlide) }

    var body: some View {
        HSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    fields
                    sectionsEditor
                    arrangementEditor
                    if let error { Text(error).foregroundStyle(.red) }
                    HStack {
                        Button(isNew ? "Add song" : "Save") { save() }.keyboardShortcut("s").buttonStyle(.borderedProminent).disabled(!canEdit || (!changed && !isNew) || saving)
                        if changed && !isNew { Button("Revert") { draft = original } }
                        if saved && !changed { Label("Saved", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                        Spacer()
                        if let onDelete { Button("Delete…", role: .destructive, action: onDelete).disabled(!canEdit) }
                    }
                }
                .padding(18)
            }
            .frame(minWidth: 380)
            preview.frame(minWidth: 220, idealWidth: 260)
        }
    }

    private var fields: some View {
        Form {
            TextField("Title", text: $draft.title)
            TextField("Authors", text: $draft.authors)
            HStack { TextField("CCLI number", text: $draft.ccliNumber); TextField("Copyright", text: $draft.copyright) }
            Stepper(value: $draft.linesPerSlide, in: 0...12) {
                Text(draft.linesPerSlide == 0 ? "Lines per slide: one slide per section" : "Lines per slide: \(draft.linesPerSlide)")
            }
        }.formStyle(.columns).disabled(!canEdit)
    }

    private var sectionsEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Sections").font(.headline)
                Spacer()
                Menu("Add section") {
                    ForEach(["Verse", "Chorus", "Pre-Chorus", "Bridge", "Tag", "Intro", "Outro"], id: \.self) { label in Button(label) { draft.sections.append(SongSection(id: SongParsers.newSectionId(draft.sections), label: label, text: "")) } }
                }.fixedSize().disabled(!canEdit)
            }
            ForEach($draft.sections) { $s in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        TextField("Label", text: $s.label).textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                        Spacer()
                        Button { duplicate(s) } label: { Image(systemName: "plus.square.on.square") }.buttonStyle(.borderless).help("Duplicate section")
                        Button(role: .destructive) { remove(s) } label: { Image(systemName: "trash") }.buttonStyle(.borderless).help("Delete section")
                    }
                    TextEditor(text: $s.text).font(.body).frame(minHeight: 84).overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                }
                .disabled(!canEdit)
            }
            if draft.sections.isEmpty { Text("Add a section, or import words from a file.").foregroundStyle(.secondary) }
        }
    }

    private var arrangementEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Custom order (repeat a chorus, skip a verse)", isOn: Binding(get: { draft.arrangement != nil }, set: { draft.arrangement = $0 ? draft.sections.map(\.id) : nil })).disabled(!canEdit)
            if let order = draft.arrangement {
                List {
                    ForEach(Array(order.enumerated()), id: \.offset) { i, id in
                        HStack {
                            Text(draft.sections.first { $0.id == id }?.label ?? "Missing section").foregroundStyle(draft.sections.contains { $0.id == id } ? Color.primary : Color.red)
                            Spacer()
                            Button { draft.arrangement?.remove(at: i) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                        }
                    }
                    .onMove { from, to in draft.arrangement?.move(fromOffsets: from, toOffset: to) }
                }
                .frame(height: min(240, CGFloat(max(1, order.count)) * 28 + 12)).listStyle(.bordered)
                Menu("Add to the order") { ForEach(draft.sections) { s in Button(s.label) { draft.arrangement?.append(s.id) } } }.fixedSize()
                let missing = draft.sections.filter { !order.contains($0.id) }
                if !missing.isEmpty { Text("Not played: \(missing.map(\.label).joined(separator: ", "))").font(.caption).foregroundStyle(.orange) }
            }
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Slides (\(slides.count))").font(.headline).padding(12)
            Divider()
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(slides.enumerated()), id: \.offset) { _, s in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(s.label).font(.caption).foregroundStyle(.secondary)
                            Text(s.text).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(10).background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "#1f3a5f").opacity(0.12)))
                    }
                    if slides.isEmpty { Text("Nothing to show yet.").foregroundStyle(.secondary) }
                }.padding(12)
            }
        }
    }

    private func duplicate(_ s: SongSection) {
        guard let i = draft.sections.firstIndex(where: { $0.id == s.id }) else { return }
        var copy = s; copy.id = SongParsers.newSectionId(draft.sections)
        draft.sections.insert(copy, at: i + 1)
    }

    private func remove(_ s: SongSection) {
        draft.sections.removeAll { $0.id == s.id }
        draft.arrangement = draft.arrangement?.filter { $0 != s.id }
    }

    private func save() {
        guard let org = app.church?.id else { return }
        if let p = draft.problem { error = p; return }
        saving = true; error = nil
        Task {
            defer { saving = false }
            do {
                guard let song = try await app.library?.saveSong(draft, organizationId: org) else { return }
                original = SongDraft(song); draft = original; saved = true
                await onSaved(song)
            } catch { self.error = Formatting.message(for: error) }
        }
    }
}

// MARK: - Import

struct ImportEntry: Identifiable {
    let id = UUID()
    var fileName: String
    var kind: String
    var source: SongSource
    var song: ParsedSong
    var action: SongImportAction?
}

private struct ImportSheet: View {
    @Environment(MenuModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Binding var entries: [ImportEntry]
    let library: [Song]
    let onDone: () async -> Void
    @State private var busy = false
    @State private var error: String?

    private func action(_ e: ImportEntry) -> SongImportAction { e.action ?? SongImportPlanner.defaultAction(for: e.song.title, in: library) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import songs").font(.title2.weight(.semibold))
            Text("Check the title and the sections before saving. SongSelect files are read with the same rules as the website; verify one real download if lyrics look wrong.").font(.callout).foregroundStyle(.secondary)
            List {
                ForEach($entries) { $e in
                    let dup = SongImportPlanner.duplicate(of: e.song.title, in: library)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            TextField("Title", text: $e.song.title).textFieldStyle(.roundedBorder)
                            Text("\(e.kind) · \(e.song.sections.count) section\(e.song.sections.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary).fixedSize()
                        }
                        Text(e.song.sections.map(\.label).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        if dup != nil {
                            Picker("Already in the library", selection: Binding(get: { action(e) }, set: { e.action = $0 })) {
                                Text("Skip").tag(SongImportAction.skip); Text("Replace the existing song").tag(SongImportAction.replace); Text("Add as a copy").tag(SongImportAction.copy)
                            }.pickerStyle(.menu).foregroundStyle(.orange)
                        }
                        if e.song.sections.isEmpty { Text("No words found in \(e.fileName).").font(.caption).foregroundStyle(.red) }
                    }.padding(.vertical, 4)
                }
            }
            .frame(minHeight: 260)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(summary) { save() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(busy || plan.add.isEmpty && plan.replace.isEmpty)
            }
        }
        .padding(20).frame(width: 600, height: 500)
    }

    private var plan: (add: [ImportEntry], replace: [(ImportEntry, Song)]) {
        var add: [ImportEntry] = []; var replace: [(ImportEntry, Song)] = []
        for e in entries where !e.song.title.trimmingCharacters(in: .whitespaces).isEmpty && !e.song.sections.isEmpty {
            let dup = SongImportPlanner.duplicate(of: e.song.title, in: library)
            switch action(e) {
            case .import: add.append(e)
            case .copy: add.append(e)
            case .replace: if let dup { replace.append((e, dup)) } else { add.append(e) }
            case .skip: break
            }
        }
        return (add, replace)
    }

    private var summary: String {
        let n = plan.add.count + plan.replace.count
        return n == 0 ? "Nothing to save" : "Save \(n) song\(n == 1 ? "" : "s")"
    }

    private func save() {
        guard let org = app.church?.id else { return }
        busy = true; error = nil
        let p = plan
        Task {
            defer { busy = false }
            do {
                let drafts = p.add.map { e -> SongDraft in
                    var d = SongDraft(parsed: e.song, source: e.source)
                    if action(e) == .copy, SongImportPlanner.duplicate(of: e.song.title, in: library) != nil { d.title = SongImportPlanner.copyTitle(d.title) }
                    return d
                }
                try await app.library?.insertSongs(drafts, organizationId: org)
                for (e, old) in p.replace {
                    var d = SongDraft(old)
                    d.title = e.song.title; d.authors = e.song.authors; d.ccliNumber = e.song.ccliNumber; d.copyright = e.song.copyright
                    d.sections = e.song.sections; d.arrangement = nil; d.source = e.source.rawValue
                    _ = try await app.library?.saveSong(d, organizationId: org)
                }
                await onDone()
                dismiss()
            } catch { self.error = Formatting.message(for: error) }
        }
    }
}

private struct PasteSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onParsed: (ImportEntry) -> Void
    @State private var title = ""
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Paste lyrics").font(.title2.weight(.semibold))
            Text("Section labels such as Verse 1 or Chorus start a new section; blank lines separate sections too. CCLI and copyright lines are picked up.").font(.callout).foregroundStyle(.secondary)
            TextField("Title (optional)", text: $title).textFieldStyle(.roundedBorder)
            TextEditor(text: $text).font(.body).frame(minHeight: 220).overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Review") {
                    let parsed = SongParsers.parsePlainText(text, titleHint: title)
                    onParsed(ImportEntry(fileName: "pasted text", kind: "pasted text", source: .paste, song: parsed))
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20).frame(width: 520, height: 460)
    }
}

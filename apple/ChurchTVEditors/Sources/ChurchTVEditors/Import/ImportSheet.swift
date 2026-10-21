import SwiftUI
import UniformTypeIdentifiers
import ChurchTVCore
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

extension Image {
    init?(imageData data: Data) {
        #if os(iOS)
        guard let u = UIImage(data: data) else { return nil }
        self.init(uiImage: u)
        #else
        guard let n = NSImage(data: data) else { return nil }
        self.init(nsImage: n)
        #endif
    }
}

/// The import screen: choose a file (or drop one on the Mac), preview and tick pages, choose where they go, upload with progress.
/// Presented by `ImportButton` from the deck editor and the playlist editor.
struct ImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var flow: ImportFlow
    @State private var choosing = false
    @State private var dropTargeted = false
    @State private var confirmClose = false

    var body: some View {
        NavigationStack {
            Group {
                switch flow.phase {
                case .choose: chooseView
                case .loading: ProgressView("Reading the file…").frame(maxWidth: .infinity, maxHeight: .infinity)
                case .preview: previewView
                case .importing: importingView
                case .finished: finishedView
                }
            }
            .navigationTitle(title)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if flow.phase != .importing { Button(flow.phase == .finished ? "Close" : "Cancel") { dismiss() }.cancelShortcut() }
                }
            }
        }
        .interactiveDismissDisabled(flow.phase == .importing)
        .fileImporter(isPresented: $choosing, allowedContentTypes: ImportFlow.fileTypes, allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): flow.load(urls: urls)
            case .failure(let error): flow.errorText = "Could not open the file: \(Formatting.message(for: error))"
            }
        }
        .macSheetFrame(minWidth: 620, minHeight: 640)
        .task { Self.debugAutoLoad(flow) }
    }

    private var title: String {
        switch flow.phase {
        case .choose, .loading: return "Import"
        case .preview: return flow.session?.name ?? "Import"
        case .importing: return "Importing"
        case .finished: return "Import finished"
        }
    }

    // MARK: Choose

    private var chooseView: some View {
        Form {
            Section {
                VStack(spacing: 14) {
                    Image(systemName: "square.and.arrow.down.on.square").font(.system(size: 44)).foregroundStyle(.tint).accessibilityHidden(true)
                    Text("Import from PowerPoint, PDF or pictures").font(.headline).multilineTextAlignment(.center)
                    Text(flow.target.isDeck
                         ? "Each page becomes a slide in this deck. PowerPoint text stays editable."
                         : "Each page becomes a picture in this playlist.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button { choosing = true } label: { Label("Choose file…", systemImage: "doc.badge.plus").frame(maxWidth: 260) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                    #if os(macOS)
                    Text("or drop a file here").font(.footnote).foregroundStyle(.secondary)
                    #endif
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 12).strokeBorder(dropTargeted ? Color.accentColor : .clear, style: StrokeStyle(lineWidth: 2, dash: [6])))
                .dropDestination(for: URL.self) { urls, _ in
                    guard !urls.isEmpty else { return false }
                    flow.load(urls: urls); return true
                } isTargeted: { dropTargeted = $0 }
            }
            if let e = flow.errorText { Section { Banner(text: e, style: .error) } }
            Section {
                Banner(text: ImportLimits.exportTip, style: .info, systemImage: "lightbulb.fill")
            } footer: {
                Text("A PowerPoint (.pptx) is read for its text, notes, pictures and videos; fonts, colours, shapes and animations are not kept. A PDF export looks exactly like the original because each page becomes a full-screen picture. \(ImportLimits.summary)")
            }
        }
        .formStyleGroupedOnMac()
    }

    // MARK: Preview

    private var previewView: some View {
        Form {
            summarySection
            placementSection
            optionsSection
            pagesSection
            if flow.hasMedia { mediaSection }
            importSection
        }
        .formStyleGroupedOnMac()
    }

    @ViewBuilder private var summarySection: some View {
        if let s = flow.session {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.name).font(.headline)
                        Text(summaryText(s)).font(.subheadline).foregroundStyle(.secondary)
                    }
                } icon: { Image(systemName: s.kind == .pptx ? "rectangle.on.rectangle" : s.kind == .pdf ? "doc.richtext" : "photo.on.rectangle").foregroundStyle(.tint) }
                ForEach(s.notices, id: \.self) { Banner(text: $0, style: .warning) }
                if s.kind == .pptx {
                    Banner(text: ImportLimits.exportTip + " Importing the .pptx keeps text editable but not the exact design.", style: .info, systemImage: "lightbulb.fill")
                }
                Button { flow.reset() } label: { Label("Choose a different file", systemImage: "arrow.uturn.backward") }
            }
        }
    }

    private func summaryText(_ s: ImportSession) -> String {
        switch s.kind {
        case .pdf: return "PDF, \(ImportBuilder.count(s.entries.count, .pdf)). Each page becomes a full-screen picture (1920 pixels on the long side)."
        case .images: return "\(ImportBuilder.count(s.entries.count, .images)), uploaded as they are."
        case .pptx:
            return flow.target.isDeck
                ? "PowerPoint, \(ImportBuilder.count(s.entries.count, .pptx)). Text becomes editable slides; slides that are only a picture become picture slides."
                : "PowerPoint, \(ImportBuilder.count(s.entries.count, .pptx)). A Kids playlist has no text slide, so each text slide is drawn as a picture (white text on your church colour). Speaker notes are not kept."
        }
    }

    private var placementSection: some View {
        Section {
            Picker("Add to", selection: $flow.placementMode) {
                Text("The end of this \(flow.target.noun)").tag(ImportFlow.PlacementMode.append)
                Text("After a position in this \(flow.target.noun)").tag(ImportFlow.PlacementMode.after)
                Text("A new \(flow.target.noun)").tag(ImportFlow.PlacementMode.new)
            }
            .pickerStyle(.inline)
            .labelsHidden()
            .accessibilityLabel("Where to add")
            if flow.placementMode == .after {
                Stepper(value: $flow.after, in: 0...flow.existingCount) {
                    Text(flow.after == 0 ? "At the start" : "After \(flow.target.itemNoun) \(flow.after) of \(flow.existingCount)")
                }
            }
            if flow.placementMode == .new {
                TextField("Name of the new \(flow.target.noun)", text: $flow.newName)
                    .accessibilityLabel("Name of the new \(flow.target.noun)")
            }
        } header: { Text("Where") } footer: {
            if flow.placementMode == .new { Text("A separate \(flow.target.noun) is created and saved. This one is not changed.") }
            else { Text("The \(flow.target.noun) is changed on screen. Tap Save in the editor to keep it.") }
        }
    }

    private var optionsSection: some View {
        Section {
            Picker("Each page shows", selection: $flow.seconds) {
                ForEach(ImportBuilder.durationChoices, id: \.self) { s in Text(ImportBuilder.durationLabel(s)).tag(s) }
            }
            HStack {
                Text("Media folder")
                TextField("Folder name", text: $flow.folderName).labelsHidden().multilineTextAlignment(.trailing)
            }
            if flow.target.isDeck && flow.hasPicturesOnTextSlides {
                Toggle("Add pictures from text slides as extra slides", isOn: $flow.withPictures)
            }
        } header: { Text("Options") } footer: {
            Text("Pictures are uploaded to a new folder with this name at the top of the \(flow.target.module.displayName) library. Videos and pictures can each be up to \(ImportLimits.uploadLimitText).")
        }
    }

    private var pagesSection: some View {
        Section {
            ForEach(Array(flow.entries.enumerated()), id: \.element.id) { i, e in
                ImportRow(flow: flow, entry: e, index: i, last: i == flow.entries.count - 1)
            }
        } header: {
            HStack {
                Text("\(flow.session.map { $0.kind.unit.capitalized + "s" } ?? "Pages"): \(flow.includedCount) of \(flow.entries.count) ticked")
                Spacer()
                Button("All") { flow.setAll(true) }.buttonStyle(.borderless).textCase(nil)
                Button("None") { flow.setAll(false) }.buttonStyle(.borderless).textCase(nil)
            }
        } footer: {
            Text("Untick what you do not want. Use the ••• menu on a row to change the order.")
        }
    }

    private var mediaSection: some View {
        Section {
            ForEach(flow.mediaEntries) { m in
                HStack(spacing: 12) {
                    Button { flow.toggleMedia(m) } label: {
                        Image(systemName: m.included && m.disabledReason == nil ? "checkmark.circle.fill" : "circle").font(.title3)
                            .foregroundStyle(m.disabledReason != nil ? Color.secondary.opacity(0.4) : m.included ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(m.disabledReason != nil)
                    .accessibilityLabel(m.included ? "Included" : "Not included")
                    Image(systemName: m.media.kind == .video ? "film" : "music.note").foregroundStyle(.secondary).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Slide \(m.slideNumber): \(m.detail)").font(.subheadline).lineLimit(2)
                        if let r = m.disabledReason { Text(r).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        } header: { Text("Videos and audio in the file") } footer: {
            Text("Ticked videos become \(flow.target.isDeck ? "video slides" : "video items") right after their slide. Audio is added to the media library only. The slide must be ticked too.")
        }
    }

    private var importSection: some View {
        Section {
            if let p = flow.problem { Text(p).font(.footnote).foregroundStyle(.orange) }
            Button { flow.run() } label: {
                Label("Import \(ImportBuilder.count(flow.includedCount, flow.kind))", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(flow.problem != nil)
        } footer: {
            Text("This can take a while for big files; keep the app open. Up to \(ImportLimits.uploadsInFlight) pages upload at once.")
        }
    }

    // MARK: Importing

    private var importingView: some View {
        Form {
            Section {
                ProgressView(value: flow.progress)
                HStack {
                    Text(flow.stopping ? "Stopping… finishing the uploads in progress" : "Importing").font(.headline)
                    Spacer()
                    Text("\(Int(flow.progress * 100))%").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                Button("Stop", role: .destructive) { flow.stop() }.disabled(flow.stopping)
            } footer: { Text("Keep the app open. Stopping keeps what is already done.") }
            Section {
                ForEach(flow.entries.filter { flow.statuses[$0.id] != nil }) { e in
                    HStack(spacing: 10) {
                        statusIcon(flow.statuses[e.id] ?? .wait)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.title).lineLimit(1)
                            statusText(flow.statuses[e.id] ?? .wait)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .formStyleGroupedOnMac()
    }

    @ViewBuilder private func statusIcon(_ s: RowStatus) -> some View {
        switch s {
        case .wait: Image(systemName: "clock").foregroundStyle(.secondary)
        case .busy: ProgressView().controlSize(.small)
        case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .fail: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .skipped: Image(systemName: "minus.circle").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func statusText(_ s: RowStatus) -> some View {
        switch s {
        case .wait: Text("Waiting").font(.caption).foregroundStyle(.secondary)
        case .busy(let p): Text("Working \(Int(min(1, p) * 100))%").font(.caption).foregroundStyle(.secondary)
        case .ok(let m): Text(m ?? "Done").font(.caption).foregroundStyle(.secondary)
        case .fail(let m): Text(m).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
        case .skipped(let m): Text(m).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Finished

    private var finishedView: some View {
        let o = flow.outcome
        return Form {
            Section {
                if let e = o.saveError {
                    Banner(text: "The pictures were uploaded to your media library, but the \(flow.target.noun) could not be saved: \(e)", style: .error)
                } else if o.added > 0 {
                    Banner(text: successText(o), style: .info, systemImage: "checkmark.circle.fill")
                } else {
                    Banner(text: o.stopped ? "Stopped before anything was added." : "Nothing could be imported. See the messages below.", style: .error)
                }
                if let fe = o.folderError { Banner(text: "The media folder could not be created (\(fe)), so files went to the top level of the library.", style: .warning) }
                ForEach(o.libraryOnly, id: \.self) { Text("\($0) added to the media library.").font(.subheadline) }
            }
            if !o.failures.isEmpty {
                Section("Could not import (\(o.failures.count))") {
                    ForEach(o.failures) { f in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.label).font(.body)
                            Text(f.reason).font(.caption).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            Section {
                Button { dismiss() } label: { Text("Done").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).defaultShortcut()
            }
        }
        .formStyleGroupedOnMac()
    }

    private func successText(_ o: ImportOutcome) -> String {
        let n = "\(o.added) \(flow.target.itemNoun)\(o.added == 1 ? "" : "s")"
        var s: String
        if let created = o.createdName { s = "Created the \(flow.target.noun) \"\(created)\" with \(n)." }
        else { s = "Added \(n) to this \(flow.target.noun). Check them, then tap Save." }
        if let f = o.folderName { s += " Files are in the \"\(f)\" folder of the Media library." }
        if o.stopped { s = "Stopped early. " + s }
        if !o.failures.isEmpty { s += " \(o.failures.count) could not be imported (below)." }
        return s
    }
}

// MARK: - Row

private struct ImportRow: View {
    var flow: ImportFlow
    var entry: ImportEntry
    var index: Int
    var last: Bool

    var body: some View {
        HStack(spacing: 12) {
            Button { flow.toggle(entry) } label: {
                Image(systemName: entry.included ? "checkmark.circle.fill" : "circle").font(.title3)
                    .foregroundStyle(!entry.enabled ? Color.secondary.opacity(0.4) : entry.included ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!entry.enabled)
            .accessibilityLabel(entry.included ? "Included" : "Not included")
            thumb.frame(width: 96)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.body).lineLimit(1)
                if !entry.detail.isEmpty { Text(entry.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                if let w = entry.warning { Text(w).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 0)
            Menu {
                Button { flow.move(entry, .top) } label: { Label("Move to top", systemImage: "arrow.up.to.line") }.disabled(index == 0)
                Button { flow.move(entry, .up) } label: { Label("Move up", systemImage: "arrow.up") }.disabled(index == 0)
                Button { flow.move(entry, .down) } label: { Label("Move down", systemImage: "arrow.down") }.disabled(last)
                Button { flow.move(entry, .bottom) } label: { Label("Move to bottom", systemImage: "arrow.down.to.line") }.disabled(last)
            } label: { Image(systemName: "ellipsis.circle").font(.title3) }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Reorder \(entry.title)")
        }
        .accessibilityElement(children: .contain)
        .task(id: entry.id) { await flow.thumbnail(for: entry) }
    }

    @ViewBuilder private var thumb: some View {
        ZStack {
            if entry.style == .text, let t = flow.text(for: entry) {
                SlidePreview(slide: DeckSlide(id: "p", content: .text(TextSlideContent(title: t.title, body: t.body))))
            } else if let d = flow.thumbs[entry.id], let img = Image(imageData: d) {
                img.resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            } else {
                Color.tertiaryFill.overlay(Image(systemName: entry.style == .empty ? "questionmark.square.dashed" : "photo").foregroundStyle(.secondary))
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.15)))
        .opacity(entry.included ? 1 : 0.45)
        .accessibilityHidden(true)
    }
}

// MARK: - Debug (screenshots)

extension ImportSheet {
    /// DEBUG launch arguments for screenshots: `-importdemo pdf|pptx|pictures` loads a generated sample file as if it had been chosen.
    static func debugAutoLoad(_ flow: ImportFlow) {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard flow.phase == .choose, let i = args.firstIndex(of: "-importdemo"), i + 1 < args.count else { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("import-demo-src", isDirectory: true)
        do {
            switch args[i + 1] {
            case "pdf":
                flow.load(urls: [try ImportSamples.write(ImportSamples.pdf(pages: 8), named: "Easter Service.pdf", in: dir)])
            case "pptx":
                flow.load(urls: [try ImportSamples.write(ImportSamples.pptx(), named: "Sunday Announcements.pptx", in: dir)])
            default:
                let a = try ImportSamples.write(ImportSamples.picture(caption: "Welcome"), named: "Welcome.png", in: dir)
                let b = try ImportSamples.write(ImportSamples.picture(caption: "Offering", hueA: (0.18, 0.49, 0.36), hueB: (0.96, 0.78, 0.2)), named: "Offering.png", in: dir)
                flow.load(urls: [a, b])
            }
        } catch { flow.errorText = Formatting.message(for: error) }
        #endif
    }
}

import SwiftUI
import ChurchTVCore

// EXPERIMENTAL NDI source UI, shared by the Kids playlist item editor and the Slides deck slide editor (dashboard/src/NdiItem.tsx).
// Only offered when the church's `organizations.ndi_enabled` flag is true (`ContentModel.ndiEnabled`). See NDI-CONTRACT.md.

/// Small orange "EXPERIMENTAL" capsule.
struct ExperimentalBadge: View {
    var text = NdiText.badge
    var body: some View {
        Text(text)
            .font(.caption2.weight(.heavy)).tracking(0.6)
            .foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Color.orange, in: Capsule())
            .accessibilityLabel("Experimental")
    }
}

/// The form for one NDI source (Form sections). `showTitle` is false only where the host already has a title field.
struct NdiFormSections: View {
    @Binding var ndi: NdiSettings

    var body: some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                ExperimentalBadge()
                Text(NdiText.needsNote).font(.footnote).foregroundStyle(.secondary)
            }
        }

        Section {
            TextField("e.g. Main camera", text: $ndi.title).accessibilityLabel("Title")
        } header: { Text("Title") }

        Section {
            TextField("STUDIO-PC (Camera 1)", text: $ndi.source)
                .plainTextInput()
                .accessibilityLabel("NDI source name")
            TextField("192.168.1.50:5961", text: Binding(get: { ndi.address ?? "" }, set: { ndi.address = $0 }))
                .urlKeyboard().plainTextInput()
                .accessibilityLabel("Address, optional")
            if !NdiSettings.isValidAddress(ndi.address ?? "") {
                Label("Use a host name or IP address with an optional :port, and no spaces.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(.orange)
            }
        } header: { Text("Source") } footer: {
            Text("The source name is exactly how NDI lists it: MACHINE (Source). Add the address only if the TV is on a different network from the source.")
        }

        Section {
            Picker("Picture", selection: $ndi.fit) {
                Text("Fit (show the whole picture)").tag(NdiFit.fit)
                Text("Fill (crop to fill the screen)").tag(NdiFit.fill)
            }
            Toggle("Play sound", isOn: $ndi.audio)
            Toggle("Stop after a set time", isOn: Binding(get: { ndi.seconds != nil }, set: { ndi.seconds = $0 ? (ndi.seconds ?? 60) : nil }))
            if ndi.seconds != nil {
                SecondsRow(title: "Show for", seconds: Binding(get: { ndi.seconds ?? 60 }, set: { ndi.seconds = $0 }), range: NdiSettings.secondsRange)
            }
        } header: { Text("Playback") } footer: {
            Text("Leave the time off to keep the picture up until Next. Sound is off unless you turn it on.")
        }

        Section {
            SecondsRow(title: "Wait for the source", seconds: $ndi.maxWaitSeconds, range: NdiSettings.maxWaitRange)
            Picker("If the source isn't available", selection: $ndi.fallback) {
                Text("Skip it").tag(NdiFallback.skip)
                Text("Show a message").tag(NdiFallback.message)
            }
            if ndi.fallback == .message {
                TextField("Waiting for the camera…", text: Binding(get: { ndi.fallbackText ?? "" }, set: { ndi.fallbackText = String($0.prefix(200)) }), axis: .vertical)
                    .lineLimit(1...3)
                    .accessibilityLabel("Fallback message")
            }
        } header: { Text("If the source drops") } footer: {
            Text("The TV waits this many seconds (3 to 120), then follows the choice above. With no message the TV shows \"Waiting for the live feed…\".")
        }

        Section {
            Label(NdiText.previewNote, systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary)
            Text(NdiText.networkHelp).font(.footnote).foregroundStyle(.secondary)
        } header: { Text("Good to know") }
    }
}

/// An NDI entry in a church where the flag is off: shown, never editable (the server refuses changes; deleting is still allowed).
struct NdiReadOnlySection: View {
    let ndi: NdiSettings

    var body: some View {
        Section {
            HStack(spacing: 10) { ExperimentalBadge(); Text("Switched off for this church").font(.subheadline.weight(.semibold)) }
            Text(NdiText.offNote).font(.footnote).foregroundStyle(.secondary)
        }
        Section {
            LabeledContent("Title", value: ndi.title.isEmpty ? "None" : ndi.title)
            LabeledContent("Source", value: ndi.source.isEmpty ? "None" : ndi.source)
            if let a = ndi.address, !a.isEmpty { LabeledContent("Address", value: a) }
            LabeledContent("Picture", value: ndi.fit == .fill ? "Fill" : "Fit")
            LabeledContent("Sound", value: ndi.audio ? "On" : "Off")
            LabeledContent("Show for", value: ndi.seconds.map { "\($0) s" } ?? "Until Next")
            LabeledContent("Wait for the source", value: "\(ndi.maxWaitSeconds) s")
            LabeledContent("If not available", value: ndi.fallback == .skip ? "Skip it" : (ndi.fallbackText ?? "").isEmpty ? "Show a message" : "Show: \(ndi.fallbackText ?? "")")
        } header: { Text("Settings") }
    }
}

/// What the preview frame draws for an NDI source: a placeholder, like the website (no NDI receiving on the phone or Mac).
struct NdiPlaceholderContent: View {
    let title: String; let source: String; let fit: NdiFit
    let width: Double; let height: Double

    var body: some View {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let src = source.trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(spacing: height * 0.024) {
            HStack(spacing: height * 0.016) {
                Image(systemName: "web.camera").font(.system(size: height * 0.04, weight: .bold))
                Text("NDI").font(.system(size: height * 0.034, weight: .heavy)).tracking(height * 0.034 * 0.1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, height * 0.024).padding(.vertical, height * 0.008)
            .background(Color(hex: "#1976d2"), in: RoundedRectangle(cornerRadius: height * 0.012))
            Text(name.isEmpty ? (src.isEmpty ? "No source chosen" : src) : name)
                .font(.system(size: height * 0.07, weight: .heavy)).foregroundStyle(.white).multilineTextAlignment(.center).minimumScaleFactor(0.5).lineLimit(2)
            if !name.isEmpty, !src.isEmpty {
                Text(src).font(.system(size: height * 0.034)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
            }
            Text("Experimental: the NDI picture appears on the TV (\(NdiText.fitNote(fit)))")
                .font(.system(size: height * 0.028)).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center).lineLimit(2)
        }
        .padding(height * 0.06)
    }
}

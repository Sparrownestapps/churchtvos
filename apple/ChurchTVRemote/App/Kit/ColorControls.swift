import SwiftUI
import ChurchTVCore

/// Preset colours the website offers for sign backgrounds and text.
enum ColorPresets {
    static let standard = ["#ffffff", "#f3efe6", "#111827", "#000000", "#b3261e", "#d9480f", "#f59e0b", "#2e7d5b", "#1d4ed8", "#7c3aed"]
}

/// A row of tappable colour dots. The selected one gets a ring. Use inside a Form/List or alone.
/// `extra` are additional named colours (for example the church's primary and accent colour) shown before the presets.
struct ColorSwatches: View {
    @Binding var selection: String
    var presets: [String] = ColorPresets.standard
    var extra: [(name: String, hex: String)] = []

    private var all: [(name: String, hex: String)] { extra + presets.map { ($0, $0) } }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(all.enumerated()), id: \.offset) { _, c in
                    let on = selection.lowercased() == c.hex.lowercased()
                    Button { selection = c.hex; Haptics.selection() } label: {
                        Circle().fill(Color(hex: c.hex)).frame(width: 30, height: 30)
                            .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 1))
                            .overlay(Circle().stroke(Color.accentColor, lineWidth: on ? 3 : 0).padding(-4))
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(c.name.hasPrefix("#") ? "Colour \(c.name)" : c.name)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }
}

/// A labelled hex colour: the system colour picker, a text field for the hex code and the preset swatches.
/// The binding always holds '#rrggbb' (an invalid hex typed by hand is not written until it is valid).
struct ColorRow: View {
    var title: String
    @Binding var hex: String
    var presets: [String] = ColorPresets.standard
    var extra: [(name: String, hex: String)] = []
    var showsSwatches = true
    @State private var draft = ""
    @FocusState private var editing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                TextField("#RRGGBB", text: $draft)
                    .focused($editing)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(.body.monospaced()).multilineTextAlignment(.trailing).frame(maxWidth: 110)
                    .onSubmit(commit)
                    .accessibilityLabel("\(title) hex code")
                ColorPicker(title, selection: Binding(get: { Color(hex: hex) }, set: { hex = $0.hexString; draft = hex }), supportsOpacity: false)
                    .labelsHidden()
            }
            if showsSwatches { ColorSwatches(selection: $hex, presets: presets, extra: extra) }
        }
        .onAppear { draft = hex }
        .onChange(of: hex) { _, new in if !editing { draft = new } }
        .onChange(of: draft) { _, new in
            let t = new.hasPrefix("#") ? new : "#" + new
            if ColorTools.isHex(t) { hex = t.lowercased() }
        }
        .onChange(of: editing) { _, isEditing in if !isEditing { commit() } }
    }

    private func commit() {
        let t = draft.hasPrefix("#") ? draft : "#" + draft
        if ColorTools.isHex(t) { hex = t.lowercased() }
        draft = hex
    }
}

/// Optional colour (a theme text colour that may be unset): a switch for "use the default" and the colour row when it is set.
struct OptionalColorRow: View {
    var title: String
    @Binding var hex: String?
    var defaultHex: String
    var presets: [String] = ColorPresets.standard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("\(title): custom", isOn: Binding(get: { hex != nil }, set: { hex = $0 ? (hex ?? defaultHex) : nil }))
            if hex != nil {
                ColorRow(title: title, hex: Binding(get: { hex ?? defaultHex }, set: { hex = $0 }), presets: presets)
            }
        }
    }
}

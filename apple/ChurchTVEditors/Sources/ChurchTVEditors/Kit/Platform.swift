import SwiftUI
import ImageIO
import ChurchTVCore
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// Cross-platform shims so the editors compile and look right on iPhone, iPad and Mac.

extension Color {
    /// Subtle fill for placeholders and thumbnails (system tertiary fill).
    static var tertiaryFill: Color {
        #if os(iOS)
        Color(.tertiarySystemFill)
        #else
        Color(nsColor: .tertiaryLabelColor).opacity(0.18)
        #endif
    }
    /// Card background inside grouped lists.
    static var groupedCard: Color {
        #if os(iOS)
        Color(.secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}

extension Image {
    init(cgImageFrame cg: CGImage) {
        #if os(iOS)
        self.init(uiImage: UIImage(cgImage: cg))
        #else
        self.init(nsImage: NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)))
        #endif
    }
}

/// JPEG bytes (quality 0.9) for any image data the system can read (HEIC, PNG, ...), or nil if it is not an image.
func jpegData(fromImageData data: Data, quality: Double = 0.9) -> Data? {
    guard let src = CGImageSourceCreateWithData(data as CFData, nil), let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    let out = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
    // Keep the orientation the camera recorded.
    var props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
    if let meta = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any], let o = meta[kCGImagePropertyOrientation] { props[kCGImagePropertyOrientation] = o }
    CGImageDestinationAddImage(dest, cg, props as CFDictionary)
    return CGImageDestinationFinalize(dest) ? out as Data : nil
}

/// Hex text ('#rrggbb') of a SwiftUI colour in sRGB.
func hexString(of color: Color) -> String {
    #if os(iOS)
    let ui = UIColor(color)
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    ui.getRed(&r, green: &g, blue: &b, alpha: &a)
    #else
    let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    ns.getRed(&r, green: &g, blue: &b, alpha: &a)
    #endif
    return ColorTools.hex(r: Int((r * 255).rounded()), g: Int((g * 255).rounded()), b: Int((b * 255).rounded()))
}

extension View {
    /// Inline navigation title on iPhone and iPad (no effect on the Mac).
    @ViewBuilder func inlineNavigationTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
    /// Words capitalised as you type (iOS only).
    @ViewBuilder func autocapitalizeWords() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.words)
        #else
        self
        #endif
    }
    /// No auto-capitalisation or autocorrect; for URLs, hex codes and ids.
    @ViewBuilder func plainTextInput() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never).autocorrectionDisabled()
        #else
        self.autocorrectionDisabled()
        #endif
    }
    @ViewBuilder func urlKeyboard() -> some View {
        #if os(iOS)
        self.keyboardType(.URL)
        #else
        self
        #endif
    }
    @ViewBuilder func numberKeyboard() -> some View {
        #if os(iOS)
        self.keyboardType(.numberPad)
        #else
        self
        #endif
    }
    @ViewBuilder func numbersAndPunctuationKeyboard() -> some View {
        #if os(iOS)
        self.keyboardType(.numbersAndPunctuation)
        #else
        self
        #endif
    }
}

// Toolbar placement names that differ per platform.
extension ToolbarItemPlacement {
    /// Trailing toolbar item: top bar trailing on iOS, automatic (right side of the toolbar) on the Mac.
    static var trailingBar: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .automatic
        #endif
    }
}

#if os(macOS)
// SwiftUI has no EditMode on the Mac (lists reorder by dragging rows). These stand-ins let the shared code compile; they do nothing.
enum EditMode { case inactive, transient, active; var isEditing: Bool { self != .inactive } }
private struct EditModeKey: EnvironmentKey { static let defaultValue: Binding<EditMode>? = nil }
extension EnvironmentValues {
    var editMode: Binding<EditMode>? {
        get { self[EditModeKey.self] }
        set { self[EditModeKey.self] = newValue }
    }
}
struct EditButton: View { var body: some View { EmptyView() } }
#endif

extension View {
    /// Pushes a list of choices on iPhone and iPad; a pop-up menu on the Mac.
    @ViewBuilder func navigationLinkPicker() -> some View {
        #if os(iOS)
        self.pickerStyle(.navigationLink)
        #else
        self.pickerStyle(.menu)
        #endif
    }
}

extension View {
    /// Search field that stays visible under the navigation bar on iPhone and iPad; in the toolbar on the Mac.
    @ViewBuilder func alwaysVisibleSearch(text: Binding<String>, prompt: String) -> some View {
        #if os(iOS)
        self.searchable(text: text, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
        #else
        self.searchable(text: text, prompt: prompt)
        #endif
    }
}

// MARK: Mac presentation

extension View {
    /// Sheets on the Mac have no detents: give them a sensible minimum size and the grouped form look. No effect on iPhone and iPad.
    @ViewBuilder func macSheetFrame(minWidth: CGFloat = 520, minHeight: CGFloat = 560) -> some View {
        #if os(macOS)
        self.formStyle(.grouped)
            .frame(minWidth: minWidth, idealWidth: minWidth + 80, minHeight: minHeight, idealHeight: minHeight + 120)
        #else
        self
        #endif
    }

    /// Pushed editors on the Mac: grouped forms, and content that does not stretch across a very wide window. No effect on iPhone and iPad.
    @ViewBuilder func macReadableWidth(_ maxWidth: CGFloat = 760) -> some View {
        #if os(macOS)
        self.formStyle(.grouped)
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
        #else
        self
        #endif
    }

    /// Cmd+S on the Mac (Save buttons).
    @ViewBuilder func saveShortcut() -> some View {
        #if os(macOS)
        self.keyboardShortcut("s", modifiers: .command)
        #else
        self
        #endif
    }

    /// Esc on the Mac (Cancel and Close buttons).
    @ViewBuilder func cancelShortcut() -> some View {
        #if os(macOS)
        self.keyboardShortcut(.cancelAction)
        #else
        self
        #endif
    }

    /// Return on the Mac (the default Done/OK button of a sheet).
    @ViewBuilder func defaultShortcut() -> some View {
        #if os(macOS)
        self.keyboardShortcut(.defaultAction)
        #else
        self
        #endif
    }
}

extension View {
    /// Grouped form look on the Mac (the default there is a plain two-column form). No effect on iPhone and iPad.
    @ViewBuilder func formStyleGroupedOnMac() -> some View {
        #if os(macOS)
        self.formStyle(.grouped)
        #else
        self
        #endif
    }
}

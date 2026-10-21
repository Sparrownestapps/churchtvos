import SwiftUI

/// A banner for warnings, errors and notes.
public struct Banner: View {
    public enum Style { case warning, error, info }
    let text: String
    var style: Style
    var systemImage: String?

    public init(text: String, style: Style = .warning, systemImage: String? = nil) {
        self.text = text; self.style = style; self.systemImage = systemImage
    }

    private var color: Color { style == .error ? .red : style == .warning ? .orange : .blue }
    private var icon: String { systemImage ?? (style == .info ? "info.circle.fill" : "exclamationmark.triangle.fill") }

    public var body: some View {
        Label {
            Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

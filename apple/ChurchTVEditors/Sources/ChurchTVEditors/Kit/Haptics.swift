#if canImport(UIKit)
import UIKit
#endif

/// Tap feedback on iPhone and iPad. On the Mac these do nothing (the trackpad gives its own feedback).
public enum Haptics {
    #if os(iOS)
    public static func tap() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    public static func heavy() { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
    public static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    public static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    public static func failure() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    #else
    public static func tap() {}
    public static func heavy() {}
    public static func selection() {}
    public static func success() {}
    public static func failure() {}
    #endif
}

import SwiftUI

#if os(iOS)
import UIKit

/// Tap, and press-and-hold then drag, as a UIKit recognizer pair. SwiftUI's sequenced LongPress + Drag gesture swallowed the scroll view's
/// pan on iPhone; a UILongPressGestureRecognizer behaves like Apple's own calendar: moving before the hold scrolls, holding first starts the drag.
struct HoldDrag: UIViewRepresentable {
    var dragEnabled = true
    var onTap: ((CGPoint) -> Void)?
    /// start and current location, in this view's coordinates.
    var onChange: (CGPoint, CGPoint) -> Void
    var onEnd: (CGPoint, CGPoint) -> Void
    var onCancel: () -> Void

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.press(_:)))
        press.minimumPressDuration = 0.35
        press.allowableMovement = 10
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        v.addGestureRecognizer(press)
        v.addGestureRecognizer(tap)
        context.coordinator.press = press
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.press?.isEnabled = dragEnabled
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: HoldDrag
        var press: UILongPressGestureRecognizer?
        var start = CGPoint.zero
        init(_ p: HoldDrag) { parent = p }

        @objc func tap(_ g: UITapGestureRecognizer) {
            if g.state == .ended { parent.onTap?(g.location(in: g.view)) }
        }

        @objc func press(_ g: UILongPressGestureRecognizer) {
            let p = g.location(in: g.view)
            switch g.state {
            case .began:
                start = p
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                parent.onChange(start, p)
            case .changed: parent.onChange(start, p)
            case .ended: parent.onEnd(start, p)
            case .cancelled, .failed: parent.onCancel()
            default: break
            }
        }
    }
}
#endif

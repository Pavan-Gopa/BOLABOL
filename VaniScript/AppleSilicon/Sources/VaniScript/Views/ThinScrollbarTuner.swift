import SwiftUI
import AppKit

struct ThinScrollbarTuner: NSViewRepresentable {
    func makeNSView(context: Context) -> ScrollbarTuningView {
        ScrollbarTuningView()
    }

    func updateNSView(_ nsView: ScrollbarTuningView, context: Context) {
        DispatchQueue.main.async {
            nsView.tuneEnclosingScrollView()
        }
    }

    final class ScrollbarTuningView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async {
                self.tuneEnclosingScrollView()
            }
        }

        func tuneEnclosingScrollView() {
            if let scrollView = enclosingScrollView {
                Self.tune(scrollView)
                return
            }

            var ancestor = superview
            while let view = ancestor {
                if let scrollView = view as? NSScrollView {
                    Self.tune(scrollView)
                }
                Self.tuneDescendantScrollViews(in: view)
                ancestor = view.superview
            }
        }

        private static func tuneDescendantScrollViews(in view: NSView) {
            for subview in view.subviews {
                if let scrollView = subview as? NSScrollView {
                    tune(scrollView)
                }
                tuneDescendantScrollViews(in: subview)
            }
        }

        private static func tune(_ scrollView: NSScrollView) {
            scrollView.scrollerStyle = .overlay
            scrollView.autohidesScrollers = true
            if !(scrollView.verticalScroller is ThinReviewScroller) {
                scrollView.verticalScroller = ThinReviewScroller()
            }
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.verticalScrollElasticity = .allowed
            scrollView.horizontalScrollElasticity = .none
        }
    }
}

private final class ThinReviewScroller: NSScroller {
    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat {
        4
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

    override func drawKnob() {
        let knobRect = rect(for: .knob)
        guard knobRect.height > 0 else { return }
        let width: CGFloat = 3
        let centered = NSRect(
            x: knobRect.midX - width / 2,
            y: knobRect.minY + 2,
            width: width,
            height: max(12, knobRect.height - 4)
        )
        NSColor.white.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: centered, xRadius: width / 2, yRadius: width / 2).fill()
    }
}

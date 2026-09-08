import AppKit
import SwiftUI

/// Finds the real AppKit `NSTextView` swift-markdown-engine mounts inside its
/// `NSScrollView`, so `MarkdownNotesView` can drive things the package's
/// public API (`NativeTextViewWrapper`) doesn't expose: its own formatting
/// actions and right-click menu (both live on `textView.delegate`, an
/// `NSTextViewDelegate` — a fully public, standard AppKit property; only the
/// *reference to that specific text view* isn't handed to embedders), first-
/// responder/cursor control, and precise (not broadcast) focus tracking.
///
/// Placed as a `.background()` on the same `NativeTextViewWrapper` node it's
/// locating for — SwiftUI composites background content close to its primary
/// view, so the search only needs to climb a few ancestors before finding the
/// `NSScrollView` sibling. Bounded and first-match-wins specifically so that,
/// with Page and Notes both visible in a split view, this can't wander far
/// enough up the tree to find the *other* editor's text view instead of its
/// own — verify this holds if a future SwiftUI layout change nests things
/// differently.
struct MarkdownTextViewLocator: NSViewRepresentable {
    let onLocate: (NSTextView) -> Void

    final class Coordinator {
        var hasLocated = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let anchor = NSView(frame: .zero)
        anchor.isHidden = true
        return anchor
    }

    /// Retries on every SwiftUI update pass (cheap: a handful of `subviews`
    /// checks) until the search succeeds once — the very first pass can run
    /// before `NativeTextViewWrapper`'s `NSScrollView` has actually been
    /// inserted into the hierarchy. Stops permanently after that, so this
    /// doesn't re-walk the view tree on every keystroke.
    func updateNSView(_ nsView: NSView, context: Context) {
        guard !context.coordinator.hasLocated else {
            return
        }

        DispatchQueue.main.async {
            guard let found = Self.findTextView(near: nsView) else {
                return
            }
            context.coordinator.hasLocated = true
            onLocate(found)
        }
    }

    private static let maxAncestorClimb = 8

    private static func findTextView(near anchor: NSView) -> NSTextView? {
        var ancestor: NSView? = anchor
        var climbed = 0
        while let current = ancestor, climbed < maxAncestorClimb {
            if let found = findTextView(in: current) {
                return found
            }
            ancestor = current.superview
            climbed += 1
        }
        return nil
    }

    private static func findTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView {
            return textView
        }
        for subview in view.subviews {
            if let found = findTextView(in: subview) {
                return found
            }
        }
        return nil
    }
}

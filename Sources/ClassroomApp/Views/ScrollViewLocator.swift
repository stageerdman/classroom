import AppKit
import SwiftUI

/// Finds the `NSScrollView` backing an enclosing SwiftUI `ScrollView`, so a
/// view can observe AppKit's live-scroll notifications
/// (`willStartLiveScroll`/`didLiveScroll`) — the only reliable way on
/// macOS 14 to tell a *user* scroll gesture apart from a programmatic
/// `scrollTo` (`onScrollPhaseChange`/`onScrollGeometryChange` are macOS 15+).
/// Those notifications fire for trackpad/wheel input but not for programmatic
/// clip-view moves.
///
/// Placed as a `.background()` inside the `ScrollView`'s content; SwiftUI
/// composites it near its primary view, so a short ancestor climb finds the
/// nearest enclosing `NSScrollView` — this view's own, not a sibling pane's.
/// Mirrors `MarkdownTextViewLocator`.
struct ScrollViewLocator: NSViewRepresentable {
    let onLocate: (NSScrollView) -> Void

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

    func updateNSView(_ nsView: NSView, context: Context) {
        guard !context.coordinator.hasLocated else {
            return
        }

        DispatchQueue.main.async {
            guard let found = Self.findScrollView(near: nsView) else {
                return
            }
            context.coordinator.hasLocated = true
            onLocate(found)
        }
    }

    private static let maxAncestorClimb = 8

    private static func findScrollView(near anchor: NSView) -> NSScrollView? {
        var ancestor: NSView? = anchor.superview
        var climbed = 0
        while let current = ancestor, climbed < maxAncestorClimb {
            if let scrollView = current as? NSScrollView {
                return scrollView
            }
            ancestor = current.superview
            climbed += 1
        }
        return nil
    }
}

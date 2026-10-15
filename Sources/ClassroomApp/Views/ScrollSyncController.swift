import AppKit

/// Keeps two editor scroll views in lockstep while "linked" is on (the
/// Page∥Notes split). Each pane registers its `NSScrollView`; a user scroll in
/// one mirrors the other's vertical offset. A re-entrancy guard stops the
/// mirror from echoing back into an endless loop.
@MainActor
final class ScrollSyncController: ObservableObject {
    /// Driven by the view's link toggle. When false, scrolls aren't mirrored.
    var isLinked = true

    private var scrollViews: [Int: NSScrollView] = [:]
    private var observers: [Int: NSObjectProtocol] = [:]
    private var isMirroring = false

    func register(_ scrollView: NSScrollView, forPane pane: Int) {
        guard scrollViews[pane] !== scrollView else {
            return
        }
        if let existing = observers[pane] {
            NotificationCenter.default.removeObserver(existing)
        }

        scrollViews[pane] = scrollView
        scrollView.contentView.postsBoundsChangedNotifications = true
        observers[pane] = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.didScroll(pane: pane) }
        }
    }

    func reset() {
        observers.values.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        scrollViews.removeAll()
        isMirroring = false
    }

    private func didScroll(pane: Int) {
        guard isLinked, !isMirroring, scrollViews.count == 2 else {
            return
        }
        let otherPane = pane == 0 ? 1 : 0
        guard let source = scrollViews[pane], let target = scrollViews[otherPane] else {
            return
        }

        isMirroring = true
        defer { isMirroring = false }

        // Mirror the absolute vertical offset (clamped to the target's own
        // scrollable range), so the panes track together even when their
        // content heights differ.
        let maxTargetY = max((target.documentView?.bounds.height ?? 0) - target.contentView.bounds.height, 0)
        let y = min(max(source.contentView.bounds.origin.y, 0), maxTargetY)
        guard abs(target.contentView.bounds.origin.y - y) > 0.5 else {
            return
        }
        target.contentView.scroll(to: NSPoint(x: target.contentView.bounds.origin.x, y: y))
        target.reflectScrolledClipView(target.contentView)
    }
}

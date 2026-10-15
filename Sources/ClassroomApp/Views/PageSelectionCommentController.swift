import AppKit
import SwiftUI

/// Shows a floating "Comment" button just above the current text selection in
/// the Page editor. Managed as a subview of the `NSTextView` itself, so it
/// lives in the text view's (flipped) coordinate space — positioned directly
/// from the selection's bounding rect and scrolling with the content, with no
/// SwiftUI↔AppKit coordinate conversion.
@MainActor
final class PageSelectionCommentController {
    private weak var textView: NSTextView?
    private var buttonHost: NSHostingView<PageCommentButton>?
    private var selectionObserver: NSObjectProtocol?
    private var onComment: ((String) -> Void)?

    func attach(to textView: NSTextView, onComment: @escaping (String) -> Void) {
        guard self.textView !== textView else {
            return
        }
        detach()
        self.textView = textView
        self.onComment = onComment

        selectionObserver = NotificationCenter.default.addObserver(
            forName: NSTextView.didChangeSelectionNotification, object: textView, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateButton() }
        }
        updateButton()
    }

    func detach() {
        if let selectionObserver {
            NotificationCenter.default.removeObserver(selectionObserver)
        }
        selectionObserver = nil
        buttonHost?.removeFromSuperview()
        buttonHost = nil
        textView = nil
        onComment = nil
    }

    private func updateButton() {
        guard
            let textView,
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        else {
            hideButton()
            return
        }

        let selection = textView.selectedRange()
        let selectedText = (textView.string as NSString).substring(with: selection)
        guard selection.length > 0, !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            hideButton()
            return
        }

        let glyphRange = layoutManager.glyphRange(forCharacterRange: selection, actualCharacterRange: nil)
        var bounds = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        bounds.origin.x += textView.textContainerOrigin.x
        bounds.origin.y += textView.textContainerOrigin.y

        let host = buttonHost ?? makeButtonHost()
        host.rootView = PageCommentButton { [weak self] in
            self?.commit(selectedText)
        }
        host.layout()
        let size = host.fittingSize

        // Just above the selection's top edge, horizontally centered on it and
        // clamped into the visible width.
        let x = min(max(bounds.midX - size.width / 2, 4), max(textView.bounds.width - size.width - 4, 4))
        let y = max(bounds.minY - size.height - 6, 2)
        host.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
        host.isHidden = false
    }

    private func commit(_ selectedText: String) {
        hideButton()
        onComment?(selectedText)
    }

    private func hideButton() {
        buttonHost?.isHidden = true
    }

    private func makeButtonHost() -> NSHostingView<PageCommentButton> {
        let host = NSHostingView(rootView: PageCommentButton(action: {}))
        host.translatesAutoresizingMaskIntoConstraints = true
        textView?.addSubview(host)
        buttonHost = host
        return host
    }
}

/// The floating pill shown above a Page selection.
struct PageCommentButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Comment", systemImage: "text.bubble")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
    }
}

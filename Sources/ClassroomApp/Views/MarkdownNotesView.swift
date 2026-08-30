import AppKit
import SwiftUI

struct MarkdownNotesView: NSViewRepresentable {
    @Binding var text: String
    @Binding var contentHeight: CGFloat
    let onTextChange: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticLinkDetectionEnabled = true
        textView.isAutomaticDashSubstitutionEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 8)
        textView.font = .systemFont(ofSize: 15)
        textView.string = text
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.applyMarkdownStyle()
        context.coordinator.updateContentHeight()

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        if textView.string != text {
            textView.string = text
            context.coordinator.applyMarkdownStyle()
        }

        context.coordinator.updateContentHeight()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, contentHeight: $contentHeight, onTextChange: onTextChange)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        @Binding private var contentHeight: CGFloat
        private let onTextChange: () -> Void
        weak var textView: NSTextView?
        private var isApplyingStyle = false

        init(text: Binding<String>, contentHeight: Binding<CGFloat>, onTextChange: @escaping () -> Void) {
            _text = text
            _contentHeight = contentHeight
            self.onTextChange = onTextChange
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }

            text = textView.string
            applyMarkdownStyle()
            updateContentHeight()
            onTextChange()
        }

        @MainActor func applyMarkdownStyle() {
            guard let textView, !isApplyingStyle else {
                return
            }

            isApplyingStyle = true
            defer { isApplyingStyle = false }

            let selectedRange = textView.selectedRange()
            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            let storage = textView.textStorage
            storage?.beginEditing()
            storage?.setAttributes([
                .font: NSFont.systemFont(ofSize: 15),
                .foregroundColor: NSColor.labelColor
            ], range: fullRange)

            let nsText = textView.string as NSString
            nsText.enumerateSubstrings(in: fullRange, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
                let line = nsText.substring(with: lineRange)
                if line.hasPrefix("# ") {
                    storage?.addAttributes([.font: NSFont.boldSystemFont(ofSize: 24)], range: lineRange)
                } else if line.hasPrefix("## ") {
                    storage?.addAttributes([.font: NSFont.boldSystemFont(ofSize: 20)], range: lineRange)
                } else if line.hasPrefix("### ") {
                    storage?.addAttributes([.font: NSFont.boldSystemFont(ofSize: 17)], range: lineRange)
                } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    storage?.addAttributes([.font: NSFont.systemFont(ofSize: 15)], range: lineRange)
                }
            }

            applyInlineMarkdown(pattern: "\\*\\*([^*]+)\\*\\*", font: .boldSystemFont(ofSize: 15))
            applyInlineMarkdown(pattern: "(?<!\\*)\\*([^*]+)\\*(?!\\*)", font: NSFontManager.shared.convert(.systemFont(ofSize: 15), toHaveTrait: .italicFontMask))

            storage?.endEditing()
            textView.setSelectedRange(selectedRange)
            updateContentHeight()
        }

        @MainActor func updateContentHeight() {
            guard
                let textView,
                let layoutManager = textView.layoutManager,
                let textContainer = textView.textContainer
            else {
                return
            }

            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let measuredHeight = max(180, ceil(usedRect.height + (textView.textContainerInset.height * 2) + 12))

            if abs(contentHeight - measuredHeight) > 1 {
                DispatchQueue.main.async {
                    self.contentHeight = measuredHeight
                }
            }

            textView.frame.size.height = measuredHeight
        }

        @MainActor private func applyInlineMarkdown(pattern: String, font: NSFont) {
            guard let textView, let storage = textView.textStorage else {
                return
            }

            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return
            }

            for match in regex.matches(in: textView.string, range: fullRange) {
                storage.addAttributes([.font: font], range: match.range)
            }
        }
    }
}

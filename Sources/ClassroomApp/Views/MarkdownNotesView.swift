import AppKit
import SwiftUI

struct MarkdownNotesView: NSViewRepresentable {
    @Binding var text: String
    @Binding var contentHeight: CGFloat
    let onTextChange: () -> Void
    /// `false` renders styled Markdown but blocks typing/selection-editing
    /// — used for Page outside Module edit mode, where the content is
    /// meant to be read, not edited.
    var isEditable: Bool = true

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
        textView.isEditable = isEditable
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

        if textView.isEditable != isEditable {
            textView.isEditable = isEditable
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

        private static let bodyFontSize: CGFloat = 15
        /// (marker, header level's displayed font size) — checked in this
        /// order; each requires an exact hash count immediately followed by
        /// a space, so a line can only ever match one of these.
        private static let headerMarkers: [(String, CGFloat)] = [
            ("###### ", 15), ("##### ", 15.5), ("#### ", 16),
            ("### ", 17), ("## ", 20), ("# ", 24)
        ]

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
                .font: NSFont.systemFont(ofSize: Self.bodyFontSize),
                .foregroundColor: NSColor.labelColor
            ], range: fullRange)

            let nsText = textView.string as NSString
            nsText.enumerateSubstrings(in: fullRange, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
                self.styleLine(nsText.substring(with: lineRange), in: lineRange, storage: storage)
            }

            applyDelimitedInlineStyle(
                pattern: "\\*\\*([^*]+)\\*\\*",
                contentGroup: 1,
                contentAttributes: [.font: NSFont.boldSystemFont(ofSize: Self.bodyFontSize), .foregroundColor: NSColor.labelColor]
            )
            applyDelimitedInlineStyle(
                pattern: "(?<!\\*)\\*([^*]+)\\*(?!\\*)",
                contentGroup: 1,
                contentAttributes: [
                    .font: NSFontManager.shared.convert(.systemFont(ofSize: Self.bodyFontSize), toHaveTrait: .italicFontMask),
                    .foregroundColor: NSColor.labelColor
                ]
            )
            applyDelimitedInlineStyle(
                pattern: "`([^`]+)`",
                contentGroup: 1,
                contentAttributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: Self.bodyFontSize - 1, weight: .regular),
                    .foregroundColor: NSColor.labelColor,
                    .backgroundColor: NSColor.textBackgroundColor.blended(withFraction: 0.5, of: .secondaryLabelColor) ?? NSColor.textBackgroundColor
                ]
            )
            applyLinkStyle()

            storage?.endEditing()
            textView.setSelectedRange(selectedRange)
            updateContentHeight()
        }

        /// Line-level constructs: headers, blockquotes, checkboxes, plain
        /// list bullets, and horizontal rules. Obsidian-style — the syntax
        /// marker itself is dimmed down to a small secondary-color prefix
        /// so the content it introduces is what actually reads as "the
        /// heading" / "the quote" / etc., rather than the raw `##`/`>`/`-`
        /// characters competing with it at the same size and weight.
        @MainActor private func styleLine(_ line: String, in lineRange: NSRange, storage: NSTextStorage?) {
            guard let storage else {
                return
            }

            if let (marker, size) = Self.headerMarkers.first(where: { line.hasPrefix($0.0) }) {
                applyMarker(marker, in: lineRange, storage: storage)
                applyContent(
                    after: marker,
                    in: lineRange,
                    storage: storage,
                    attributes: [.font: NSFont.boldSystemFont(ofSize: size), .foregroundColor: NSColor.labelColor]
                )
                return
            }

            if line.hasPrefix("> ") {
                applyMarker("> ", in: lineRange, storage: storage)
                applyContent(
                    after: "> ",
                    in: lineRange,
                    storage: storage,
                    attributes: [
                        .font: NSFontManager.shared.convert(.systemFont(ofSize: Self.bodyFontSize), toHaveTrait: .italicFontMask),
                        .foregroundColor: NSColor.secondaryLabelColor
                    ]
                )
                return
            }

            if let checkboxMatch = Self.checkboxRegex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                let markerLength = checkboxMatch.range.length
                let isChecked = (line as NSString).substring(with: checkboxMatch.range(at: 1)).lowercased() == "x"
                let markerRange = NSRange(location: lineRange.location, length: markerLength)
                let contentRange = NSRange(location: lineRange.location + markerLength, length: lineRange.length - markerLength)
                storage.addAttributes([.font: NSFont.systemFont(ofSize: Self.bodyFontSize), .foregroundColor: NSColor.tertiaryLabelColor], range: markerRange)
                storage.addAttributes(
                    isChecked
                        ? [.font: NSFont.systemFont(ofSize: Self.bodyFontSize), .foregroundColor: NSColor.secondaryLabelColor, .strikethroughStyle: NSUnderlineStyle.single.rawValue]
                        : [.font: NSFont.systemFont(ofSize: Self.bodyFontSize), .foregroundColor: NSColor.labelColor],
                    range: contentRange
                )
                return
            }

            for bullet in ["- ", "* ", "+ "] where line.hasPrefix(bullet) {
                applyMarker(bullet, in: lineRange, storage: storage)
                return
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.count >= 3, Set(["-", "*", "_"]).contains(where: { trimmed == String(repeating: $0, count: trimmed.count) }) {
                storage.addAttributes([.font: NSFont.systemFont(ofSize: Self.bodyFontSize), .foregroundColor: NSColor.tertiaryLabelColor], range: lineRange)
            }
        }

        private func applyMarker(_ marker: String, in lineRange: NSRange, storage: NSTextStorage) {
            let markerRange = NSRange(location: lineRange.location, length: min(marker.utf16.count, lineRange.length))
            storage.addAttributes([.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.tertiaryLabelColor], range: markerRange)
        }

        private func applyContent(after marker: String, in lineRange: NSRange, storage: NSTextStorage, attributes: [NSAttributedString.Key: Any]) {
            let markerLength = min(marker.utf16.count, lineRange.length)
            let contentRange = NSRange(location: lineRange.location + markerLength, length: lineRange.length - markerLength)
            guard contentRange.length > 0 else {
                return
            }
            storage.addAttributes(attributes, range: contentRange)
        }

        private static let checkboxRegex = try! NSRegularExpression(pattern: "^[-*+] \\[([ xX])\\] ")

        /// `[text](url)` — the link text is styled and made clickable
        /// (Cmd-click, standard AppKit behavior for `.link`-attributed
        /// text); the brackets/parens/URL portion is dimmed like every
        /// other marker.
        @MainActor private func applyLinkStyle() {
            guard let textView, let storage = textView.textStorage else {
                return
            }

            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            guard let regex = try? NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(([^)]+)\\)") else {
                return
            }

            let nsText = textView.string as NSString
            for match in regex.matches(in: textView.string, range: fullRange) {
                let textRange = match.range(at: 1)
                let urlRange = match.range(at: 2)
                guard textRange.location != NSNotFound, urlRange.location != NSNotFound else {
                    continue
                }

                storage.addAttributes([.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.tertiaryLabelColor], range: match.range)

                var linkAttributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: Self.bodyFontSize),
                    .foregroundColor: NSColor.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ]
                if let url = URL(string: nsText.substring(with: urlRange)) {
                    linkAttributes[.link] = url
                }
                storage.addAttributes(linkAttributes, range: textRange)
            }
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

        /// A `marker CONTENT marker`-shaped inline construct (bold, italic,
        /// inline code, ...): the whole match is dimmed as a marker first,
        /// then `contentAttributes` overrides just the captured content
        /// group, restoring its color/font to something that reads as
        /// actual styled text rather than muted syntax.
        @MainActor private func applyDelimitedInlineStyle(pattern: String, contentGroup: Int, contentAttributes: [NSAttributedString.Key: Any]) {
            guard let textView, let storage = textView.textStorage else {
                return
            }

            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return
            }

            for match in regex.matches(in: textView.string, range: fullRange) {
                storage.addAttributes([.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.tertiaryLabelColor], range: match.range)

                let contentRange = match.range(at: contentGroup)
                if contentRange.location != NSNotFound {
                    storage.addAttributes(contentAttributes, range: contentRange)
                }
            }
        }
    }
}

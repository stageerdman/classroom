import AppKit
import ClassroomCore
import SwiftUI

struct MarkdownNotesView: NSViewRepresentable {
    @Binding var text: String
    @Binding var contentHeight: CGFloat
    let onTextChange: () -> Void
    /// `false` renders styled Markdown but blocks typing/selection-editing
    /// — used for Page outside Module edit mode, where the content is
    /// meant to be read, not edited.
    var isEditable: Bool = true
    /// Notion-style slash command: typing `/timenote` then Enter calls
    /// this for the text to substitute in (a `TimenoteFormat.linePrefix`
    /// built from the current playback position). `nil` disables the
    /// slash command entirely — only the Notes editor wires this up.
    var onTimenoteSlashCommand: (() -> String)?
    /// Fires when a rendered timenote timestamp pill is clicked, with the
    /// timestamp in seconds — the caller seeks playback to it.
    var onTimenoteClick: ((Double) -> Void)?
    /// Bumped by the caller to move focus into this editor and place the
    /// cursor at the end — used after inserting a timenote from the
    /// transport bar's comment button so the user can start typing.
    var focusRequest: Int = 0
    /// Fires when this editor becomes/resigns first responder — the
    /// caller uses this to disable the video transport bar's arrow-key
    /// skip shortcuts while text is focused, so arrow keys navigate text
    /// instead of skipping playback.
    var onFocusChange: ((Bool) -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = MarkdownTextView()
        textView.delegate = context.coordinator
        textView.onFormatShortcut = { [weak coordinator = context.coordinator] shortcut in
            coordinator?.applyFormatShortcut(shortcut) ?? false
        }
        textView.onFocusChange = { [weak coordinator = context.coordinator] isFocused in
            coordinator?.onFocusChange?(isFocused)
        }
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

        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            let endOfText = NSRange(location: (textView.string as NSString).length, length: 0)
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(endOfText)
            textView.scrollRangeToVisible(endOfText)
        }

        context.coordinator.onTimenoteSlashCommand = onTimenoteSlashCommand
        context.coordinator.onTimenoteClick = onTimenoteClick
        context.coordinator.onFocusChange = onFocusChange

        context.coordinator.updateContentHeight()
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(text: $text, contentHeight: $contentHeight, onTextChange: onTextChange)
        coordinator.onTimenoteSlashCommand = onTimenoteSlashCommand
        coordinator.onTimenoteClick = onTimenoteClick
        coordinator.onFocusChange = onFocusChange
        return coordinator
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        static let timenoteURLScheme = "classroom-timenote"

        @Binding private var text: String
        @Binding private var contentHeight: CGFloat
        private let onTextChange: () -> Void
        var onTimenoteSlashCommand: (() -> String)?
        var onTimenoteClick: ((Double) -> Void)?
        var onFocusChange: ((Bool) -> Void)?
        weak var textView: NSTextView?
        private var isApplyingStyle = false
        var lastFocusRequest = 0

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

        /// Notion-style `/timenote` + Enter: swaps the typed command for a
        /// timenote line prefix and consumes the Enter keystroke (the
        /// prefix's trailing space is where typing continues, on the same
        /// line, rather than starting a new one).
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard replacementString == "\n", let onTimenoteSlashCommand else {
                return true
            }

            let nsText = textView.string as NSString
            let lineRange = nsText.lineRange(for: NSRange(location: affectedCharRange.location, length: 0))
            let lineBeforeCursor = nsText.substring(
                with: NSRange(location: lineRange.location, length: affectedCharRange.location - lineRange.location)
            )

            guard lineBeforeCursor == "/timenote" else {
                return true
            }

            let replacementRange = NSRange(location: lineRange.location, length: affectedCharRange.location - lineRange.location)
            textView.insertText(onTimenoteSlashCommand(), replacementRange: replacementRange)
            return false
        }

        /// Cmd-click (standard AppKit behavior for `.link`-attributed text)
        /// on a rendered timenote pill seeks playback instead of the
        /// default "open this URL" behavior.
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard
                let url = link as? URL,
                url.scheme == Self.timenoteURLScheme,
                let seconds = Double(url.absoluteString.dropFirst(Self.timenoteURLScheme.count + 1))
            else {
                return false
            }

            onTimenoteClick?(seconds)
            return true
        }

        /// Cmd-B/I/U: wraps the current selection in the matching markdown
        /// marker (or unwraps it, if the selection is already wrapped),
        /// mirroring standard macOS text-editing shortcuts. Underline has
        /// no CommonMark syntax, so it uses inline HTML (`<u>...</u>`),
        /// which markdown renderers pass through untouched.
        @MainActor func applyFormatShortcut(_ shortcut: MarkdownTextView.FormatShortcut) -> Bool {
            guard let textView, textView.isEditable else {
                return false
            }

            let marker: String
            switch shortcut {
            case .bold: marker = "**"
            case .italic: marker = "*"
            case .underline: marker = "__"
            }

            let nsText = textView.string as NSString
            let selectedRange = textView.selectedRange()
            let markerLength = marker.utf16.count

            // Toggle off: the markers are the first/last characters of the
            // selection itself. The boundary checks guard against bold
            // ("**") and italic ("*") sharing a character — e.g. selecting
            // "word" inside "***word***" (bold+italic stacked) must not
            // mistake either outer "*" for the *other* marker's delimiter.
            if selectedRange.length >= markerLength * 2 {
                let leadingRange = NSRange(location: selectedRange.location, length: markerLength)
                let trailingRange = NSRange(location: NSMaxRange(selectedRange) - markerLength, length: markerLength)
                if nsText.substring(with: leadingRange) == marker, nsText.substring(with: trailingRange) == marker,
                   !Self.isMarkerCharacter(at: selectedRange.location - 1, matching: marker, in: nsText),
                   !Self.isMarkerCharacter(at: NSMaxRange(selectedRange), matching: marker, in: nsText) {
                    let innerText = nsText.substring(with: NSRange(location: leadingRange.location + markerLength, length: selectedRange.length - markerLength * 2))
                    textView.insertText(innerText, replacementRange: selectedRange)
                    textView.setSelectedRange(NSRange(location: selectedRange.location, length: innerText.utf16.count))
                    return true
                }
            }

            // Toggle off: the markers immediately surround the selection.
            let beforeRange = NSRange(location: selectedRange.location - markerLength, length: markerLength)
            let afterRange = NSRange(location: NSMaxRange(selectedRange), length: markerLength)
            if beforeRange.location >= 0, NSMaxRange(afterRange) <= nsText.length,
               nsText.substring(with: beforeRange) == marker, nsText.substring(with: afterRange) == marker,
               !Self.isMarkerCharacter(at: beforeRange.location - 1, matching: marker, in: nsText),
               !Self.isMarkerCharacter(at: NSMaxRange(afterRange), matching: marker, in: nsText) {
                let combinedRange = NSRange(location: beforeRange.location, length: markerLength + selectedRange.length + markerLength)
                let innerText = nsText.substring(with: selectedRange)
                textView.insertText(innerText, replacementRange: combinedRange)
                textView.setSelectedRange(NSRange(location: beforeRange.location, length: innerText.utf16.count))
                return true
            }

            // Wrap. With no selection, this leaves the cursor between the
            // two markers, ready to type.
            let selectedText = nsText.substring(with: selectedRange)
            textView.insertText(marker + selectedText + marker, replacementRange: selectedRange)
            textView.setSelectedRange(NSRange(location: selectedRange.location + markerLength, length: selectedText.utf16.count))
            return true
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

            // The line(s) touching the cursor/selection reveal their raw
            // markdown syntax; every other line has its markers hidden
            // entirely (see `markerAttributes(isFocused:)`) — Obsidian's
            // live-preview behavior.
            let focusedLineRange = nsText.lineRange(for: selectedRange)

            // Collected so the inline passes below (bold/italic/code/
            // highlight/links) can skip header lines entirely — those
            // already got their whole-line font size from `styleLine`,
            // and a regex match for e.g. `**bold**` inside a header would
            // otherwise stomp that back down to normal body size for just
            // the matched substring.
            var headerLineRanges: [NSRange] = []

            nsText.enumerateSubstrings(in: fullRange, options: [.byLines, .substringNotRequired]) { substring, lineRange, _, _ in
                let isFocused = Self.isLineFocused(lineRange, focusedLineRange: focusedLineRange)
                let line = substring ?? nsText.substring(with: lineRange)
                if Self.headerMarkers.contains(where: { line.hasPrefix($0.0) }) {
                    headerLineRanges.append(lineRange)
                }
                self.styleLine(line, in: lineRange, storage: storage, isFocused: isFocused)
            }

            applyDelimitedInlineStyle(
                pattern: "\\*\\*([^*]+)\\*\\*",
                contentGroup: 1,
                contentAttributes: [.font: NSFont.boldSystemFont(ofSize: Self.bodyFontSize), .foregroundColor: NSColor.labelColor],
                focusedLineRange: focusedLineRange,
                excludedRanges: headerLineRanges
            )
            applyDelimitedInlineStyle(
                pattern: "(?<!\\*)\\*([^*]+)\\*(?!\\*)",
                contentGroup: 1,
                contentAttributes: [
                    .font: NSFontManager.shared.convert(.systemFont(ofSize: Self.bodyFontSize), toHaveTrait: .italicFontMask),
                    .foregroundColor: NSColor.labelColor
                ],
                focusedLineRange: focusedLineRange,
                excludedRanges: headerLineRanges
            )
            applyDelimitedInlineStyle(
                pattern: "`([^`]+)`",
                contentGroup: 1,
                contentAttributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: Self.bodyFontSize - 1, weight: .regular),
                    .foregroundColor: NSColor.labelColor,
                    .backgroundColor: NSColor.textBackgroundColor.blended(withFraction: 0.5, of: .secondaryLabelColor) ?? NSColor.textBackgroundColor
                ],
                focusedLineRange: focusedLineRange,
                excludedRanges: headerLineRanges
            )
            // Underline (`__text__`, what Cmd-U inserts — CommonMark has no
            // native syntax for it) — a dedicated pass, not the generic
            // delimited-style helper above, because it must never touch
            // the content's font/color (only `.underlineStyle`), so it
            // composes with whatever bold/italic/code already styled the
            // same text instead of overwriting it, regardless of order.
            applyUnderlineStyle(focusedLineRange: focusedLineRange, excludedRanges: headerLineRanges)
            applyDelimitedInlineStyle(
                pattern: "==([^=]+)==",
                contentGroup: 1,
                contentAttributes: [
                    .font: NSFont.systemFont(ofSize: Self.bodyFontSize),
                    .foregroundColor: NSColor.labelColor,
                    .backgroundColor: NSColor.systemYellow.withAlphaComponent(0.35)
                ],
                focusedLineRange: focusedLineRange,
                excludedRanges: headerLineRanges
            )
            applyLinkStyle(focusedLineRange: focusedLineRange, excludedRanges: headerLineRanges)

            storage?.endEditing()
            textView.setSelectedRange(selectedRange)
            updateContentHeight()
        }

        /// `true` if `lineRange` (one line from the `.byLines` enumeration,
        /// so its bounds already align with paragraph boundaries) falls
        /// inside `focusedLineRange` (the whole-line span touching the
        /// current selection, from `NSString.lineRange(for:)`).
        /// `true` if the character at `index` equals `marker`'s (repeated)
        /// character — used to tell a standalone marker apart from one
        /// character within a longer run of the same character (so a lone
        /// `*` found next to a selection isn't mistaken for one of the two
        /// stars in a `**` that happens to sit right next to it).
        private static func isMarkerCharacter(at index: Int, matching marker: String, in nsText: NSString) -> Bool {
            guard index >= 0, index < nsText.length, let markerCharacter = marker.first else {
                return false
            }
            return nsText.substring(with: NSRange(location: index, length: 1)) == String(markerCharacter)
        }

        private static func isLineFocused(_ lineRange: NSRange, focusedLineRange: NSRange) -> Bool {
            lineRange.location >= focusedLineRange.location
                && lineRange.location < focusedLineRange.location + max(focusedLineRange.length, 1)
        }

        /// Overlap check for a regex match against the focused line span —
        /// used where styling is applied by regex across the whole text
        /// rather than line by line (links, bold/italic/code/highlight).
        private static func isRangeFocused(_ range: NSRange, focusedLineRange: NSRange) -> Bool {
            NSMaxRange(range) > focusedLineRange.location && range.location < NSMaxRange(focusedLineRange)
        }

        /// Markdown syntax markers are fully visible (small, dimmed) only
        /// on the line currently being edited; everywhere else they're
        /// shrunk to the point of invisibility so the styled content reads
        /// clean, Obsidian-style.
        private static func markerAttributes(isFocused: Bool) -> [NSAttributedString.Key: Any] {
            isFocused
                ? [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.tertiaryLabelColor]
                : [.font: NSFont.systemFont(ofSize: 0.01), .foregroundColor: NSColor.clear]
        }

        /// Line-level constructs: headers, blockquotes, checkboxes, plain
        /// list bullets, and horizontal rules. Obsidian-style — the syntax
        /// marker itself is dimmed down to a small secondary-color prefix
        /// so the content it introduces is what actually reads as "the
        /// heading" / "the quote" / etc., rather than the raw `##`/`>`/`-`
        /// characters competing with it at the same size and weight.
        @MainActor private func styleLine(_ line: String, in lineRange: NSRange, storage: NSTextStorage?, isFocused: Bool) {
            guard let storage else {
                return
            }

            if let (marker, size) = Self.headerMarkers.first(where: { line.hasPrefix($0.0) }) {
                applyMarker(marker, in: lineRange, storage: storage, isFocused: isFocused)
                applyContent(
                    after: marker,
                    in: lineRange,
                    storage: storage,
                    attributes: [.font: NSFont.boldSystemFont(ofSize: size), .foregroundColor: NSColor.labelColor]
                )
                return
            }

            if let (timestampSeconds, _) = TimenoteFormat.parseLine(line) {
                styleTimenoteLine(timestampSeconds: timestampSeconds, in: lineRange, storage: storage, isFocused: isFocused)
                return
            }

            if line.hasPrefix("> ") {
                applyMarker("> ", in: lineRange, storage: storage, isFocused: isFocused)
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
                storage.addAttributes(Self.markerAttributes(isFocused: isFocused), range: markerRange)
                storage.addAttributes(
                    isChecked
                        ? [.font: NSFont.systemFont(ofSize: Self.bodyFontSize), .foregroundColor: NSColor.secondaryLabelColor, .strikethroughStyle: NSUnderlineStyle.single.rawValue]
                        : [.font: NSFont.systemFont(ofSize: Self.bodyFontSize), .foregroundColor: NSColor.labelColor],
                    range: contentRange
                )
                return
            }

            for bullet in ["- ", "* ", "+ "] where line.hasPrefix(bullet) {
                applyMarker(bullet, in: lineRange, storage: storage, isFocused: isFocused)
                return
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.count >= 3, Set(["-", "*", "_"]).contains(where: { trimmed == String(repeating: $0, count: trimmed.count) }) {
                storage.addAttributes(Self.markerAttributes(isFocused: isFocused), range: lineRange)
            }
        }

        /// `> [!timenote HH:MM:SS.mmm] text` — the callout header dims like
        /// any other marker, except the timestamp itself, which renders as
        /// a clickable pill (`.link` to a `classroom-timenote:` URL; see
        /// `textView(_:clickedOnLink:at:)`).
        @MainActor private func styleTimenoteLine(timestampSeconds: Double, in lineRange: NSRange, storage: NSTextStorage, isFocused: Bool) {
            let prefixText = TimenoteFormat.linePrefix(timestampSeconds: timestampSeconds)
            let prefixLength = min(prefixText.utf16.count, lineRange.length)
            let markerLength = min(TimenoteFormat.linePrefixMarker.utf16.count, prefixLength)
            let closingLength = min(2, prefixLength - markerLength)

            let markerRange = NSRange(location: lineRange.location, length: markerLength)
            storage.addAttributes(Self.markerAttributes(isFocused: isFocused), range: markerRange)

            // The timestamp pill itself always stays visible — it's the
            // clickable affordance, not syntax to hide.
            let timestampRange = NSRange(location: lineRange.location + markerLength, length: max(0, prefixLength - markerLength - closingLength))
            var pillAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.controlAccentColor,
                .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.15)
            ]
            if let url = URL(string: "\(Self.timenoteURLScheme):\(timestampSeconds)") {
                pillAttributes[.link] = url
            }
            storage.addAttributes(pillAttributes, range: timestampRange)

            let closingRange = NSRange(location: lineRange.location + markerLength + timestampRange.length, length: closingLength)
            storage.addAttributes(Self.markerAttributes(isFocused: isFocused), range: closingRange)

            let contentRange = NSRange(location: lineRange.location + prefixLength, length: lineRange.length - prefixLength)
            if contentRange.length > 0 {
                storage.addAttributes([.font: NSFont.systemFont(ofSize: Self.bodyFontSize), .foregroundColor: NSColor.labelColor], range: contentRange)
            }
        }

        private func applyMarker(_ marker: String, in lineRange: NSRange, storage: NSTextStorage, isFocused: Bool) {
            let markerRange = NSRange(location: lineRange.location, length: min(marker.utf16.count, lineRange.length))
            storage.addAttributes(Self.markerAttributes(isFocused: isFocused), range: markerRange)
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
        @MainActor private func applyLinkStyle(focusedLineRange: NSRange, excludedRanges: [NSRange]) {
            guard let textView, let storage = textView.textStorage else {
                return
            }

            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            guard let regex = try? NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(([^)]+)\\)") else {
                return
            }

            let nsText = textView.string as NSString
            for match in regex.matches(in: textView.string, range: fullRange) {
                if Self.rangeOverlapsAny(match.range, excludedRanges) {
                    continue
                }

                let textRange = match.range(at: 1)
                let urlRange = match.range(at: 2)
                guard textRange.location != NSNotFound, urlRange.location != NSNotFound else {
                    continue
                }

                let isFocused = Self.isRangeFocused(match.range, focusedLineRange: focusedLineRange)
                storage.addAttributes(Self.markerAttributes(isFocused: isFocused), range: match.range)

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

        /// `__text__` — unlike the other delimited constructs, only the
        /// `__` marker characters get dimmed; the content's font/color is
        /// left completely alone (only `.underlineStyle` is added), so
        /// underline composes with an overlapping bold/italic/code match
        /// instead of overwriting it.
        @MainActor private func applyUnderlineStyle(focusedLineRange: NSRange, excludedRanges: [NSRange]) {
            guard let textView, let storage = textView.textStorage else {
                return
            }

            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            guard let regex = try? NSRegularExpression(pattern: "__([^_]+)__") else {
                return
            }

            for match in regex.matches(in: textView.string, range: fullRange) {
                if Self.rangeOverlapsAny(match.range, excludedRanges) {
                    continue
                }

                let contentRange = match.range(at: 1)
                guard contentRange.location != NSNotFound else {
                    continue
                }

                let isFocused = Self.isRangeFocused(match.range, focusedLineRange: focusedLineRange)
                let leadingMarkerRange = NSRange(location: match.range.location, length: contentRange.location - match.range.location)
                let trailingMarkerRange = NSRange(location: NSMaxRange(contentRange), length: NSMaxRange(match.range) - NSMaxRange(contentRange))

                storage.addAttributes(Self.markerAttributes(isFocused: isFocused), range: leadingMarkerRange)
                storage.addAttributes(Self.markerAttributes(isFocused: isFocused), range: trailingMarkerRange)
                storage.addAttributes([.underlineStyle: NSUnderlineStyle.single.rawValue], range: contentRange)
            }
        }

        /// A `marker CONTENT marker`-shaped inline construct (bold, italic,
        /// inline code, ...): the whole match is dimmed as a marker first,
        /// then `contentAttributes` overrides just the captured content
        /// group, restoring its color/font to something that reads as
        /// actual styled text rather than muted syntax.
        @MainActor private func applyDelimitedInlineStyle(
            pattern: String,
            contentGroup: Int,
            contentAttributes: [NSAttributedString.Key: Any],
            focusedLineRange: NSRange,
            excludedRanges: [NSRange]
        ) {
            guard let textView, let storage = textView.textStorage else {
                return
            }

            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return
            }

            for match in regex.matches(in: textView.string, range: fullRange) {
                if Self.rangeOverlapsAny(match.range, excludedRanges) {
                    continue
                }

                let isFocused = Self.isRangeFocused(match.range, focusedLineRange: focusedLineRange)
                storage.addAttributes(Self.markerAttributes(isFocused: isFocused), range: match.range)

                let contentRange = match.range(at: contentGroup)
                if contentRange.location != NSNotFound {
                    storage.addAttributes(contentAttributes, range: contentRange)
                }
            }
        }

        /// `true` if `range` overlaps any of `excludedRanges` — used to
        /// keep header lines' whole-line font size from being overwritten
        /// by an inline match (bold/italic/code/highlight/link) that
        /// happens to fall inside one.
        private static func rangeOverlapsAny(_ range: NSRange, _ excludedRanges: [NSRange]) -> Bool {
            excludedRanges.contains { NSMaxRange(range) > $0.location && range.location < NSMaxRange($0) }
        }
    }
}

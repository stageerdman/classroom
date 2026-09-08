import AppKit
import ClassroomCore
import MarkdownEngine
import SwiftUI

/// Thin SwiftUI wrapper around swift-markdown-engine's `NativeTextViewWrapper`
/// — see `updates/2026-09-08 MARKDOWN-ENGINE - OPEN/update.md` for why this
/// replaced the app's own hand-rolled `NSTextView` styler. The external API
/// is unchanged from before the swap, so `PageEditorView`/`NotesEditorView`/
/// `MarkdownFileSheet` didn't need to change.
struct MarkdownNotesView: View {
    @Binding var text: String
    @Binding var contentHeight: CGFloat
    let onTextChange: () -> Void
    /// A stable identifier for the document being edited (e.g. a lesson's
    /// relative path, or a file path for `MarkdownFileSheet`) — keeps the
    /// engine's per-document undo stack and scroll position from bleeding
    /// across different documents shown by the same editor instance.
    var documentId: String
    /// `false` renders styled Markdown but blocks typing/selection-editing
    /// — used for Page outside Module edit mode, where the content is
    /// meant to be read, not edited.
    var isEditable: Bool = true
    /// Notion-style slash command: typing `/timenote` then Enter calls
    /// this for the text to substitute in (a `TimenoteFormat.linePrefix`
    /// built from the current playback position). `nil` disables the
    /// slash command entirely — only the Notes editor wires this up.
    var onTimenoteSlashCommand: (() -> String)?
    /// Fires when a rendered timenote pill is clicked, with the timestamp
    /// in seconds — the caller seeks playback to it.
    var onTimenoteClick: ((Double) -> Void)?
    /// No engine equivalent exists yet (see the update note above) — kept as
    /// a parameter so call sites don't need to change, but currently inert.
    var focusRequest: Int = 0
    /// No engine equivalent exists yet (see the update note above) — kept as
    /// a parameter so call sites don't need to change, but currently inert.
    var onFocusChange: ((Bool) -> Void)?

    private static let configuration = MarkdownEditorConfiguration(
        heightBehavior: .fitsContent,
        directives: [TimenoteDirective()]
    )

    var body: some View {
        NativeTextViewWrapper(
            text: Binding(
                get: { text },
                set: { newValue in
                    text = newValue
                    onTextChange()
                }
            ),
            configuration: Self.configuration,
            fontSize: 15,
            documentId: documentId,
            isEditable: isEditable,
            onLinkClick: handleLinkClick,
            onTextMutation: handleTextMutation
        )
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { contentHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, newHeight in contentHeight = newHeight }
            }
        )
    }

    private func handleLinkClick(_ target: String) {
        guard
            target.hasPrefix(TimenoteDirective.clickTargetPrefix),
            let seconds = Double(target.dropFirst(TimenoteDirective.clickTargetPrefix.count))
        else {
            return
        }

        onTimenoteClick?(seconds)
    }

    /// Notion-style `/timenote` + Enter: the engine has already committed the
    /// newline by the time this fires (there's no way to intercept the
    /// keystroke before it lands, unlike the old direct-`NSTextView`
    /// delegate), so this detects the just-completed `/timenote\n` and swaps
    /// it for the directive line a moment later instead.
    private func handleTextMutation(_ mutation: MarkdownTextMutation) {
        guard let onTimenoteSlashCommand, mutation.replacement == "\n", mutation.range.location > 0 else {
            return
        }

        let ns = text as NSString
        let lineRange = ns.lineRange(for: NSRange(location: mutation.range.location - 1, length: 0))
        let line = ns.substring(with: lineRange)
        guard line.hasSuffix("\n"), line.dropLast() == "/timenote" else {
            return
        }

        text = ns.replacingCharacters(in: lineRange, with: onTimenoteSlashCommand())
        onTextChange()
    }
}

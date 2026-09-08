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
    /// Bumped by the caller to move focus into this editor and place the
    /// cursor at the end — used after inserting a timenote from the
    /// transport bar's comment button so the user can start typing.
    var focusRequest: Int = 0
    /// Fires when this editor becomes/resigns first responder — the
    /// caller uses this to disable the video transport bar's arrow-key
    /// skip shortcuts while text is focused, so arrow keys navigate text
    /// instead of skipping playback.
    var onFocusChange: ((Bool) -> Void)?

    @State private var locatedTextView: NSTextView?
    @State private var beginEditingObserver: NSObjectProtocol?
    @State private var endEditingObserver: NSObjectProtocol?

    private static let configuration = MarkdownEditorConfiguration(
        heightBehavior: .fitsContent,
        extensions: [HighlightExtension(), StrikethroughExtension()],
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
            onTextMutation: handleTextMutation,
            onBuildContextMenu: buildContextMenu
        )
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { contentHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, newHeight in contentHeight = newHeight }
            }
        )
        .background(MarkdownTextViewLocator { locatedTextView = $0 })
        .onChange(of: locatedTextView) { _, newValue in updateFocusObservers(for: newValue) }
        .onChange(of: focusRequest) { _, _ in focusAndMoveCursorToEnd() }
        .onReceive(NotificationCenter.default.publisher(for: .markdownFormatRequested), perform: handleFormatRequest)
        .onDisappear { updateFocusObservers(for: nil) }
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

    /// The engine ships no built-in right-click menu (API-only, by design —
    /// see `ContextMenu.swift` upstream); this adds one back with the same
    /// formatting actions it used to offer.
    private func buildContextMenu(_ menu: NSMenu, _ selection: NSRange) -> NSMenu {
        guard let locatedTextView else {
            return menu
        }

        MarkdownFormattingAction.appendFormattingItems(to: menu, for: locatedTextView)
        return menu
    }

    /// Cmd-B/Cmd-I/etc. from the app's Format menu (`ClassroomApp.swift`)
    /// arrive as a broadcast, since the engine's coordinator isn't in the
    /// AppKit responder chain — only act if this specific editor's text
    /// view is the one currently focused.
    private func handleFormatRequest(_ notification: Notification) {
        guard
            let locatedTextView,
            locatedTextView.window?.firstResponder === locatedTextView,
            let rawAction = notification.userInfo?["action"] as? String,
            let action = MarkdownFormattingAction(rawValue: rawAction)
        else {
            return
        }

        action.perform(on: locatedTextView)
    }

    /// No engine callback reports focus changes, so this observes the
    /// standard AppKit `NSText` editing notifications directly, scoped via
    /// `object:` to this editor's own text view specifically — necessary
    /// since the app has other, unrelated text fields (lesson/category
    /// rename, etc.) that must NOT toggle this and block the video
    /// transport's arrow-key skip while someone renames something elsewhere.
    private func updateFocusObservers(for textView: NSTextView?) {
        if let beginEditingObserver {
            NotificationCenter.default.removeObserver(beginEditingObserver)
        }
        if let endEditingObserver {
            NotificationCenter.default.removeObserver(endEditingObserver)
        }
        beginEditingObserver = nil
        endEditingObserver = nil

        guard let textView else {
            return
        }

        let callback = onFocusChange
        beginEditingObserver = NotificationCenter.default.addObserver(
            forName: NSText.didBeginEditingNotification, object: textView, queue: .main
        ) { _ in
            callback?(true)
        }
        endEditingObserver = NotificationCenter.default.addObserver(
            forName: NSText.didEndEditingNotification, object: textView, queue: .main
        ) { _ in
            callback?(false)
        }
    }

    private func focusAndMoveCursorToEnd() {
        guard let locatedTextView else {
            return
        }

        locatedTextView.window?.makeFirstResponder(locatedTextView)
        let endRange = NSRange(location: (locatedTextView.string as NSString).length, length: 0)
        locatedTextView.setSelectedRange(endRange)
        locatedTextView.scrollRangeToVisible(endRange)
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

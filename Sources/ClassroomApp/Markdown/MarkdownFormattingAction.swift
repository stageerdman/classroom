import AppKit
import SwiftUI

/// Dispatches to swift-markdown-engine's own formatting actions
/// (`didMarkdownBold`, `didMarkdownItalic`, etc. — defined upstream in
/// `NativeTextViewCoordinator`'s `ContextMenu.swift`) by their Objective-C
/// selector. The methods are `@objc` but not `public`, so a raw `Selector`
/// + `NSObject.perform(_:with:)` is the only way to reach them from outside
/// the package — Swift's access control only gates static/compile-time
/// member lookup, not Objective-C message sends. This intentionally reuses
/// the engine's own bold/italic/highlight/strikethrough logic (it correctly
/// collapses `***both***` toggling either mark down to just the other)
/// rather than reimplementing marker wrapping/unwrapping ourselves, which is
/// exactly what caused stacking bugs in this app's previous hand-rolled
/// version.
///
/// `.highlight` and `.strikethrough` only round-trip correctly (detecting
/// and unwrapping an existing span, not just wrapping a new one) when
/// `HighlightExtension`/`StrikethroughExtension` are registered on the
/// editor's `MarkdownEditorConfiguration` — see `MarkdownNotesView`.
enum MarkdownFormattingAction: String, CaseIterable {
    case bold = "didMarkdownBold:"
    case italic = "didMarkdownItalic:"
    case highlight = "didMarkdownHighlight:"
    case strikethrough = "didMarkdownStrikethrough:"
    case inlineCode = "didMarkdownInlineCode:"
    case blockquote = "didMarkdownBlockquote:"
    case unorderedList = "didMarkdownUnorderedList:"
    case orderedList = "didMarkdownOrderedList:"
    case codeBlock = "didMarkdownCodeBlock:"
    case horizontalRule = "didMarkdownHorizontalRule:"
    case link = "didMarkdownLink:"
    case image = "didMarkdownImage:"

    var menuTitle: String {
        switch self {
        case .bold: "Bold"
        case .italic: "Italic"
        case .highlight: "Highlight"
        case .strikethrough: "Strikethrough"
        case .inlineCode: "Inline Code"
        case .blockquote: "Blockquote"
        case .unorderedList: "Bulleted List"
        case .orderedList: "Numbered List"
        case .codeBlock: "Code Block"
        case .horizontalRule: "Horizontal Rule"
        case .link: "Link"
        case .image: "Image"
        }
    }

    /// Sends this action to `textView`'s delegate — the engine's
    /// coordinator, which owns `textView` and performs the actual edit.
    /// A `sender` of `nil` is fine for every case: `.link`/`.image` read an
    /// optional URL out of an `NSNotification` sender and fall back to an
    /// empty `()`/`()`  placeholder when there isn't one, which is exactly
    /// the "insert brackets, let the user fill in the URL" behavior wanted
    /// here — there's no prompt UI for a URL.
    @MainActor
    func perform(on textView: NSTextView) {
        guard let delegate = textView.delegate as? NSObject else {
            return
        }

        let selector = Selector(rawValue)
        guard delegate.responds(to: selector) else {
            return
        }

        _ = delegate.perform(selector, with: nil)
    }

    /// Formatting actions worth a keyboard shortcut in the app's Format
    /// menu (see `ClassroomApp.swift`) — headings/lists/links/etc. are
    /// context-menu-only, matching what a plain menu click most naturally
    /// covers.
    static let keyboardShortcuts: [(action: MarkdownFormattingAction, key: String, modifiers: EventModifiers)] = [
        (.bold, "b", [.command]),
        (.italic, "i", [.command]),
        (.highlight, "h", [.command, .shift]),
        (.strikethrough, "x", [.command, .shift]),
        (.inlineCode, "e", [.command])
    ]

    /// Appends a right-click menu section covering every action the
    /// engine's own (removed) built-in menu used to offer — see
    /// `MarkdownNotesView.onBuildContextMenu`.
    @MainActor
    static func appendFormattingItems(to menu: NSMenu, for textView: NSTextView) {
        guard let target = textView.delegate as? NSObject else {
            return
        }

        menu.addItem(.separator())

        let headingMenu = NSMenu()
        for level in 1...6 {
            let item = NSMenuItem(title: "Heading \(level)", action: Selector(("didMarkdownHeading:")), keyEquivalent: "")
            item.tag = level
            item.target = target
            headingMenu.addItem(item)
        }
        let headingItem = NSMenuItem(title: "Heading", action: nil, keyEquivalent: "")
        headingItem.submenu = headingMenu
        menu.addItem(headingItem)

        for action in Self.allCases {
            let item = NSMenuItem(title: action.menuTitle, action: Selector(action.rawValue), keyEquivalent: "")
            item.target = target
            menu.addItem(item)
        }
    }
}

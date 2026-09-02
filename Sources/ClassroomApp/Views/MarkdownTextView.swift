import AppKit

/// Plain `NSTextView` isn't hooked up to markdown-aware Cmd-B/I/U — this
/// intercepts those key equivalents before the default responder chain
/// swallows them, and asks `onFormatShortcut` to actually wrap/unwrap the
/// current selection.
final class MarkdownTextView: NSTextView {
    enum FormatShortcut {
        case bold
        case italic
        case underline
    }

    /// Returns `true` if the shortcut was handled (e.g. `false` while
    /// read-only, so the event falls through to default handling).
    var onFormatShortcut: ((FormatShortcut) -> Bool)?

    /// Fires on become/resign first responder — lets the surrounding view
    /// disable the video transport bar's unmodified Left/Right arrow-key
    /// skip shortcuts while this text view has focus, so arrow keys move
    /// the text cursor instead of skipping playback.
    var onFocusChange: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let didBecomeFirstResponder = super.becomeFirstResponder()
        if didBecomeFirstResponder {
            onFocusChange?(true)
        }
        return didBecomeFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        let didResignFirstResponder = super.resignFirstResponder()
        if didResignFirstResponder {
            onFocusChange?(false)
        }
        return didResignFirstResponder
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard
            event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command],
            let characters = event.charactersIgnoringModifiers?.lowercased()
        else {
            return super.performKeyEquivalent(with: event)
        }

        let shortcut: FormatShortcut?
        switch characters {
        case "b": shortcut = .bold
        case "i": shortcut = .italic
        case "u": shortcut = .underline
        default: shortcut = nil
        }

        if let shortcut, onFormatShortcut?(shortcut) == true {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }
}

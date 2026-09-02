import SwiftUI
import WebKit

/// A request to insert a timenote at `seconds`, e.g. from the transport
/// bar's comment-icon button. `id` is a monotonically increasing token so
/// `BlockNoteEditorView` can tell a new request apart from the same one
/// re-delivered on an unrelated SwiftUI update.
struct TimenoteInsertRequest: Equatable {
    let id: Int
    let seconds: Double
}

/// Markdown editor backed by BlockNote (see
/// `updates/2026-09-02 BLOCKNOTE-EDITOR - OPEN/update.md`), running in a
/// `WKWebView` and bridged to/from plain markdown text so the rest of the
/// app — `PageService`/`NotesService`, autosave, the split view — is
/// unaware anything changed. `page.md`/`note.md` stay ordinary markdown
/// files; BlockNote is purely the in-app editing surface.
struct BlockNoteEditorView: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool = true
    var currentPlaybackSeconds: Double = 0
    var timenoteInsertRequest: TimenoteInsertRequest?
    var onTimenoteClick: ((Double) -> Void)?
    var onFocusChange: ((Bool) -> Void)?
    let onTextChange: () -> Void

    func makeNSView(context: Context) -> BlockNoteWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "classroomBridge")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.setURLSchemeHandler(
            BlockNoteSchemeHandler(resourceSubdirectory: "BlockNoteEditor"),
            forURLScheme: BlockNoteSchemeHandler.scheme
        )

        let webView = BlockNoteWebView(frame: .zero, configuration: configuration)
        webView.onFocusChange = { [weak coordinator = context.coordinator] isFocused in
            coordinator?.onFocusChange?(isFocused)
        }
        context.coordinator.webView = webView

        if let url = URL(string: "\(BlockNoteSchemeHandler.scheme)://local/index.html") {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateNSView(_ webView: BlockNoteWebView, context: Context) {
        context.coordinator.onTimenoteClick = onTimenoteClick
        context.coordinator.onFocusChange = onFocusChange
        context.coordinator.update(
            text: text,
            isEditable: isEditable,
            currentPlaybackSeconds: currentPlaybackSeconds,
            timenoteInsertRequest: timenoteInsertRequest
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onTextChange: onTextChange)
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler {
        @Binding private var text: String
        private let onTextChange: () -> Void
        var onTimenoteClick: ((Double) -> Void)?
        var onFocusChange: ((Bool) -> Void)?
        weak var webView: WKWebView?

        /// Set once the web app's `useEffect` has registered
        /// `window.classroomBridge` and posted `{type: "ready"}` — calls
        /// made before this would hit `window.classroomBridge` while
        /// it's still `undefined`.
        private var isBridgeReady = false
        private var lastKnownText: String?
        private var lastKnownEditable: Bool?
        private var lastPushedPlaybackSeconds: Double?
        private var lastHandledTimenoteInsertRequestID: Int?
        private var desiredEditable = true

        init(text: Binding<String>, onTextChange: @escaping () -> Void) {
            _text = text
            self.onTextChange = onTextChange
        }

        func update(text: String, isEditable: Bool, currentPlaybackSeconds: Double, timenoteInsertRequest: TimenoteInsertRequest?) {
            desiredEditable = isEditable
            pushContentIfNeeded(text, isEditable: isEditable, force: false)
            pushPlaybackSecondsIfNeeded(currentPlaybackSeconds)
            applyTimenoteInsertRequestIfNeeded(timenoteInsertRequest)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else {
                return
            }

            switch type {
            case "ready":
                isBridgeReady = true
                pushContentIfNeeded(text, isEditable: desiredEditable, force: true)
            case "contentChanged":
                guard let markdown = body["markdown"] as? String else {
                    return
                }
                lastKnownText = markdown
                text = markdown
                onTextChange()
            case "timenoteClicked":
                guard let seconds = body["seconds"] as? Double else {
                    return
                }
                onTimenoteClick?(seconds)
            default:
                break
            }
        }

        /// Reloads the editor's content only when `text` changed for a
        /// reason other than the editor's own last-reported edit (i.e.
        /// `lastKnownText` already matches) — otherwise every keystroke
        /// would round-trip through a full markdown reparse, fighting the
        /// user's typing and resetting their cursor.
        private func pushContentIfNeeded(_ text: String, isEditable: Bool, force: Bool) {
            guard isBridgeReady, let webView else {
                return
            }

            if force || text != lastKnownText {
                lastKnownText = text
                lastKnownEditable = isEditable
                evaluate(webView, "window.classroomBridge && window.classroomBridge.loadMarkdown(\(jsString(text)), \(isEditable))")
            } else if isEditable != lastKnownEditable {
                lastKnownEditable = isEditable
                evaluate(webView, "window.classroomBridge && window.classroomBridge.setEditable(\(isEditable))")
            }
        }

        private func pushPlaybackSecondsIfNeeded(_ seconds: Double) {
            guard isBridgeReady, let webView, seconds != lastPushedPlaybackSeconds else {
                return
            }
            lastPushedPlaybackSeconds = seconds
            evaluate(webView, "window.classroomBridge && window.classroomBridge.setCurrentPlaybackSeconds(\(seconds))")
        }

        private func applyTimenoteInsertRequestIfNeeded(_ request: TimenoteInsertRequest?) {
            guard
                isBridgeReady,
                let webView,
                let request,
                request.id != lastHandledTimenoteInsertRequestID
            else {
                return
            }

            lastHandledTimenoteInsertRequestID = request.id
            webView.window?.makeFirstResponder(webView)
            evaluate(webView, "window.classroomBridge && window.classroomBridge.insertTimenoteAtEnd(\(request.seconds))")
        }

        private func evaluate(_ webView: WKWebView, _ javaScript: String) {
            webView.evaluateJavaScript(javaScript, completionHandler: nil)
        }

        /// JSON string encoding doubles as a safe JS string literal —
        /// markdown text can contain quotes, backslashes, newlines, all
        /// of which need escaping before being spliced into a JS call.
        private func jsString(_ value: String) -> String {
            guard let data = try? JSONEncoder().encode(value), let json = String(data: data, encoding: .utf8) else {
                return "\"\""
            }
            return json
        }
    }
}

/// Tracks AppKit-level focus (become/resign first responder) so the
/// video transport bar can disable its arrow-key skip shortcuts while
/// this editor has focus — mirrors `MarkdownTextView.onFocusChange`.
final class BlockNoteWebView: WKWebView {
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
}

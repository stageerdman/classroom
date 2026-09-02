import SwiftUI
import WebKit

/// Dev-only evaluation window for BlockNote (see
/// `updates/2026-09-02 BLOCKNOTE-SPIKE - OPEN/update.md`) — loads the
/// bundled static React/BlockNote build via `BlockNoteSchemeHandler`
/// rather than `file://` (WebKit refuses `<script type="module">`, which
/// Vite's output uses, over `file://`). No bridge to Swift, no file
/// load/save: purely to evaluate the editing feel and whether embedding
/// it is tractable, in isolation from the real lesson UI.
struct BlockNoteSpikeView: View {
    var body: some View {
        BlockNoteWebView()
            .frame(minWidth: 720, minHeight: 560)
    }
}

private struct BlockNoteWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(BlockNoteSchemeHandler(), forURLScheme: BlockNoteSchemeHandler.scheme)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        if let url = URL(string: "\(BlockNoteSchemeHandler.scheme)://local/index.html") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}
}

import SwiftUI
import WebKit

/// Dev-only evaluation window for BlockNote (see
/// `updates/2026-09-02 BLOCKNOTE-SPIKE - OPEN/update.md`) — loads the
/// bundled static React/BlockNote build from
/// `Resources/BlockNoteSpike/index.html`. No bridge to Swift, no file
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
        let webView = WKWebView()
        if let indexURL = Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "BlockNoteSpike") {
            webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}
}

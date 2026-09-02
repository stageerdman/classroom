import WebKit

/// Serves the bundled BlockNote spike build over a custom URL scheme
/// instead of `file://`. WebKit refuses to load `<script type="module">`
/// (what Vite's build output uses) over `file://` — there's no origin for
/// CORS to key off of — so a scheme with a real origin is required even
/// though everything's still local/offline. Requests for
/// `classroom-blocknote://local/<path>` are mapped to
/// `Resources/BlockNoteSpike/<path>` in the app bundle.
final class BlockNoteSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "classroom-blocknote"

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard
            let url = urlSchemeTask.request.url,
            let fileURL = Self.resourceURL(for: url),
            let data = try? Data(contentsOf: fileURL)
        else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let response = URLResponse(
            url: url,
            mimeType: Self.mimeType(for: fileURL.pathExtension),
            expectedContentLength: data.count,
            textEncodingName: nil
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    /// `classroom-blocknote://local/assets/index-XXXX.js` → the matching
    /// file inside the bundled `BlockNoteSpike` resource directory. An
    /// empty or missing path resolves to `index.html`.
    private static func resourceURL(for requestURL: URL) -> URL? {
        let path = requestURL.path.isEmpty || requestURL.path == "/" ? "/index.html" : requestURL.path
        let relativePath = String(path.dropFirst())
        guard let resourceURL = Bundle.module.resourceURL else {
            return nil
        }
        return resourceURL.appendingPathComponent("BlockNoteSpike").appendingPathComponent(relativePath)
    }

    private static func mimeType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "html": return "text/html"
        case "js", "mjs": return "text/javascript"
        case "css": return "text/css"
        case "json": return "application/json"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        default: return "application/octet-stream"
        }
    }
}

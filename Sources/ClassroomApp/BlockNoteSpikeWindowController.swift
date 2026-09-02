import AppKit
import SwiftUI

/// Opens the dev-only BlockNote evaluation window (see
/// `updates/2026-09-02 BLOCKNOTE-SPIKE - OPEN/update.md`) as an ordinary,
/// resizable `NSWindow` — mirrors `FullScreenPlayerWindowController`'s
/// lazily-created, single-instance pattern rather than introducing
/// SwiftUI's `WindowGroup(id:)`/`openWindow` for just this one case.
@MainActor
final class BlockNoteSpikeWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func present() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(contentViewController: NSHostingController(rootView: BlockNoteSpikeView()))
        window.title = "BlockNote Spike"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 900, height: 680))
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

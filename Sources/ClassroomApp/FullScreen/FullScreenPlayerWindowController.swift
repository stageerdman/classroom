import AppKit
import AVFoundation
import ClassroomCore
import SwiftUI

/// Presents lesson video playback in its own real macOS full-screen window
/// (the standard green-button transition) rather than fullscreening the
/// whole app window — the sidebar/notes/attachments stay exactly where
/// they are underneath. Exiting full screen (via this window's own
/// transport-bar button, Escape, or the system green button) closes the
/// popped-out window; playback keeps going in the still-embedded player.
@MainActor
final class FullScreenPlayerWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func present(
        player: AVPlayer,
        playbackService: PlaybackService,
        thumbnailProvider: ScrubThumbnailProvider
    ) {
        guard window == nil else {
            return
        }

        let content = FullScreenPlayerView(
            player: player,
            playbackService: playbackService,
            thumbnailProvider: thumbnailProvider,
            onExitRequested: { [weak self] in self?.exitFullScreen() }
        )

        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.styleMask = [.titled, .fullSizeContentView, .closable, .resizable]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.collectionBehavior = [.fullScreenPrimary]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 960, height: 600))
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window

        // Enter full screen once the window has actually appeared, so the
        // system transition animates from a visible window instead of
        // racing its own creation.
        DispatchQueue.main.async {
            window.toggleFullScreen(nil)
        }
    }

    private func exitFullScreen() {
        window?.toggleFullScreen(nil)
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        dismiss()
    }

    private func dismiss() {
        guard let window else {
            return
        }

        window.delegate = nil
        self.window = nil
        window.close()
    }
}

private struct FullScreenPlayerView: View {
    let player: AVPlayer
    @ObservedObject var playbackService: PlaybackService
    @ObservedObject var thumbnailProvider: ScrubThumbnailProvider
    let onExitRequested: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            PlayerView(player: player)
                .ignoresSafeArea()

            VideoTransportControlsView(
                playbackService: playbackService,
                thumbnailProvider: thumbnailProvider,
                isFullScreen: true,
                onToggleFullScreen: onExitRequested
            )
            .padding(32)
        }
        .onExitCommand(perform: onExitRequested)
    }
}

import AppKit
import AVFoundation
import ClassroomCore
import SwiftUI

/// Detaches lesson video playback into its own always-on-top floating
/// window that the user can drag anywhere and resize, distinct from
/// `FullScreenPlayerWindowController`'s full-screen transition — this is
/// an ordinary window at `.floating` level, not a system full-screen
/// space. The caller is expected to hide its own embedded video surface
/// while this is presented (see `onClose`), since showing the same
/// `AVPlayer` in two places on screen at once would be confusing.
@MainActor
final class PopoutPlayerWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var onClose: (() -> Void)?

    var isPresented: Bool {
        window != nil
    }

    func present(
        player: AVPlayer,
        playbackService: PlaybackService,
        thumbnailProvider: ScrubThumbnailProvider,
        onClose: @escaping () -> Void
    ) {
        guard window == nil else {
            return
        }

        self.onClose = onClose

        let content = PopoutPlayerView(
            player: player,
            playbackService: playbackService,
            thumbnailProvider: thumbnailProvider
        )

        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = "Classroom"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 480, height: 270))
        window.contentAspectRatio = NSSize(width: 16, height: 9)
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    /// Force-closes the popout if one is open — used both when the user
    /// asks to bring the video back inline, and when the selected lesson
    /// changes so a stale player instance never lingers on screen.
    func dismissIfPresented() {
        guard let window else {
            return
        }

        window.delegate = nil
        self.window = nil
        window.close()
        onClose?()
        onClose = nil
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        onClose?()
        onClose = nil
    }
}

private struct PopoutPlayerView: View {
    let player: AVPlayer
    @ObservedObject var playbackService: PlaybackService
    @ObservedObject var thumbnailProvider: ScrubThumbnailProvider

    var body: some View {
        ZStack(alignment: .bottom) {
            PlayerView(player: player)

            VideoTransportControlsView(
                playbackService: playbackService,
                thumbnailProvider: thumbnailProvider,
                isFullScreen: false,
                onToggleFullScreen: {},
                showsFullScreenButton: false,
                showsPopoutButton: false
            )
            .padding(8)
        }
        .background(Color.black)
    }
}

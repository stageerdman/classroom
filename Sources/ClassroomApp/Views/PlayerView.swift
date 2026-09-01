import AVKit
import SwiftUI

struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        // Bare video surface — transport controls are our own
        // `VideoTransportControlsView`, so we get consistent skip/scrub/
        // full-screen behavior instead of fighting AVKit's built-in chrome.
        playerView.controlsStyle = .none
        playerView.videoGravity = .resizeAspect
        playerView.allowsPictureInPicturePlayback = true
        playerView.player = player
        return playerView
    }

    func updateNSView(_ playerView: AVPlayerView, context: Context) {
        if playerView.player !== player {
            playerView.player = player
        }
    }

    static func dismantleNSView(_ playerView: AVPlayerView, coordinator: ()) {
        playerView.player?.pause()
        playerView.player = nil
    }
}

import AppKit
import ClassroomCore
import SwiftUI

/// Custom transport bar overlaid on the bare `PlayerView` surface: play/
/// pause, ±15s skip, a scrubber with hover preview, mute, and full-screen.
/// Exists because AVPlayerView's built-in macOS chrome doesn't support
/// 15s skip or scrub-hover thumbnails, so once those were needed we own
/// the whole bar rather than mixing native and custom controls.
struct VideoTransportControlsView: View {
    @ObservedObject var playbackService: PlaybackService
    @ObservedObject var thumbnailProvider: ScrubThumbnailProvider
    let isFullScreen: Bool
    let onToggleFullScreen: () -> Void
    var onTogglePopout: () -> Void = {}

    /// Hidden for audio lessons — there's no full-screen video to enter.
    var showsFullScreenButton: Bool = true

    /// Hidden for audio lessons (nothing to pop out) and inside the
    /// full-screen window itself (pop out from full-screen isn't a
    /// supported flow — exit full-screen first).
    var showsPopoutButton: Bool = true

    /// `true` when this bar floats over a video surface (needs
    /// white-on-black contrast regardless of app theme); `false` for the
    /// standalone audio bar, which sits directly in the lesson detail
    /// pane and should use normal system control colors instead.
    var looksLikeOverlay: Bool = true

    /// Inserts a timenote in Notes at the current playback position.
    var onInsertTimenote: () -> Void = {}

    /// `true` while a Page/Notes text editor has keyboard focus — disables
    /// the bare Left/Right arrow-key skip shortcuts below so arrow keys
    /// navigate text instead of skipping playback. Space still toggles
    /// play/pause regardless, matching normal player conventions (a
    /// focused text editor would consume Space as a character anyway).
    var disableArrowKeySkip: Bool = false

    @State private var imageCache = ThumbnailImageCache()
    @State private var wasPlayingBeforeScrub = false

    private var tintColor: Color {
        looksLikeOverlay ? .white : .primary
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: playbackService.togglePlayPause) {
                Image(systemName: playbackService.isPlaying ? "pause.fill" : "play.fill")
            }
            .keyboardShortcut(.space, modifiers: [])
            .help(playbackService.isPlaying ? "Pause" : "Play")

            Group {
                if disableArrowKeySkip {
                    Button { playbackService.skipBackward() } label: {
                        Image(systemName: "gobackward.15")
                    }
                } else {
                    Button { playbackService.skipBackward() } label: {
                        Image(systemName: "gobackward.15")
                    }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                }
            }
            .help("Back 15 seconds")

            Group {
                if disableArrowKeySkip {
                    Button { playbackService.skipForward() } label: {
                        Image(systemName: "goforward.15")
                    }
                } else {
                    Button { playbackService.skipForward() } label: {
                        Image(systemName: "goforward.15")
                    }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                }
            }
            .help("Forward 15 seconds")

            Text(formatPlaybackTime(playbackService.currentTimeSeconds))
                .monospacedDigit()

            ScrubberView(
                currentTime: playbackService.currentTimeSeconds,
                duration: playbackService.durationSeconds ?? 0,
                thumbnailProvider: thumbnailProvider,
                imageForFrame: { imageCache.image(for: $0.imageURL) },
                tintColor: tintColor,
                onScrub: scrub,
                onScrubEnded: scrubEnded
            )

            Text(formatPlaybackTime(playbackService.durationSeconds ?? 0))
                .monospacedDigit()

            Button(action: playbackService.toggleMute) {
                Image(systemName: playbackService.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .help(playbackService.isMuted ? "Unmute" : "Mute")

            Button(action: onInsertTimenote) {
                Image(systemName: "text.bubble")
            }
            .help("Add a timestamped note here")

            if showsPopoutButton {
                Button(action: onTogglePopout) {
                    Image(systemName: "pip.enter")
                }
                .help("Pop Out")
            }

            if showsFullScreenButton {
                Button(action: onToggleFullScreen) {
                    Image(systemName: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
                .help(isFullScreen ? "Exit Full Screen" : "Enter Full Screen")
            }
        }
        .font(.system(size: 13))
        .buttonStyle(.plain)
        .foregroundStyle(tintColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            looksLikeOverlay ? AnyShapeStyle(.black.opacity(0.55)) : AnyShapeStyle(Color(nsColor: .controlBackgroundColor)),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    /// Fires continuously while dragging the scrubber: pause for the
    /// duration of the drag (resuming on release, if it was playing) so
    /// scrubbing doesn't fight ongoing playback.
    private func scrub(to time: Double) {
        if !wasPlayingBeforeScrub, playbackService.isPlaying {
            wasPlayingBeforeScrub = true
            playbackService.pause()
        }
        playbackService.seek(to: time)
    }

    private func scrubEnded(at time: Double) {
        playbackService.seek(to: time)
        if wasPlayingBeforeScrub {
            playbackService.play()
            wasPlayingBeforeScrub = false
        }
    }
}

/// Plain reference type (not itself `@Published`) so caching a decoded
/// thumbnail doesn't count as SwiftUI state mutation during a child
/// view's body evaluation — only the `NSCache` contents change, not the
/// `@State` holding this instance.
private final class ThumbnailImageCache {
    private let cache = NSCache<NSURL, NSImage>()

    func image(for url: URL) -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        guard let image = NSImage(contentsOf: url) else {
            return nil
        }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

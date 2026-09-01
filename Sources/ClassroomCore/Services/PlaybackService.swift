import AVFoundation
import Foundation

@MainActor
public final class PlaybackService: ObservableObject {
    /// Containers AVFoundation has never had a demuxer for — recognized as
    /// lesson media by the scanner (so they aren't silently treated as
    /// stray files) but guaranteed to fail here. Callers can check this to
    /// short-circuit straight to the actionable message instead of waiting
    /// on the async player-item failure.
    public static let knownUnplayableContainerExtensions: Set<String> = ["flv"]

    /// Extensions with no video track — the lesson card should show a
    /// bare transport bar for these instead of a video surface.
    public static let audioOnlyExtensions: Set<String> = ["mp3", "m4a", "wav"]

    /// Default skip amount for `skipForward()`/`skipBackward()`.
    public static let skipIntervalSeconds: Double = 15

    @Published public private(set) var player: AVPlayer?
    @Published public private(set) var currentURL: URL?
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var playbackRate: Float = 1
    @Published public private(set) var currentTimeSeconds: Double = 0
    @Published public private(set) var durationSeconds: Double?
    @Published public private(set) var isPlaying: Bool = false
    @Published public private(set) var isMuted: Bool = false
    @Published public private(set) var isAudioOnly: Bool = false

    private var periodicTimeObserver: Any?
    private var statusObservation: NSKeyValueObservation?

    public init() {}

    public func load(url: URL) {
        let standardizedURL = url.standardizedFileURL

        guard FileManager.default.fileExists(atPath: standardizedURL.path) else {
            player = nil
            currentURL = nil
            errorMessage = "Video file is missing: \(standardizedURL.path)"
            return
        }

        removePeriodicObserver()
        statusObservation?.invalidate()

        let fileExtension = standardizedURL.pathExtension.lowercased()

        if Self.knownUnplayableContainerExtensions.contains(fileExtension) {
            player = nil
            currentURL = standardizedURL
            errorMessage = Self.unplayableContainerMessage(for: standardizedURL)
            return
        }

        let asset = AVURLAsset(url: standardizedURL)
        let item = AVPlayerItem(asset: asset)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.isMuted = isMuted
        player = newPlayer
        currentURL = standardizedURL
        errorMessage = nil
        playbackRate = 1
        currentTimeSeconds = 0
        durationSeconds = nil
        isPlaying = false
        isAudioOnly = Self.audioOnlyExtensions.contains(fileExtension)
        installPeriodicObserver()
        observeItemStatus(item, sourceURL: standardizedURL)
    }

    private static func unplayableContainerMessage(for url: URL) -> String {
        let ext = url.pathExtension.uppercased()
        return "\(ext) isn't supported by macOS's built-in video player (AVFoundation has no \(ext) demuxer). Convert it to MP4 or MOV to play it here."
    }

    private func observeItemStatus(_ item: AVPlayerItem, sourceURL: URL) {
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else {
                return
            }
            Task { @MainActor in
                self?.handlePlaybackFailure(sourceURL: sourceURL, underlying: item.error)
            }
        }
    }

    private func handlePlaybackFailure(sourceURL: URL, underlying: Error?) {
        // A stale callback from an item that's since been replaced by a
        // newer `load(url:)` call — ignore it.
        guard currentURL == sourceURL else {
            return
        }

        player = nil
        errorMessage = underlying?.localizedDescription ?? "The selected media could not be loaded."
    }

    public func play() {
        player?.playImmediately(atRate: playbackRate)
        isPlaying = true
    }

    public func pause() {
        player?.pause()
        isPlaying = false
    }

    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    public func seek(to seconds: Double) {
        let clampedUpper = durationSeconds.map { min(seconds, $0) } ?? seconds
        player?.seek(to: CMTime(seconds: max(0, clampedUpper), preferredTimescale: 600))
    }

    public func skipForward(_ seconds: Double = PlaybackService.skipIntervalSeconds) {
        seek(to: currentTimeSeconds + seconds)
    }

    public func skipBackward(_ seconds: Double = PlaybackService.skipIntervalSeconds) {
        seek(to: currentTimeSeconds - seconds)
    }

    public func resume(to seconds: Double) {
        seek(to: seconds)
    }

    public func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
    }

    public func setPlaybackRate(_ rate: Float) {
        let supportedRates: [Float] = [0.5, 1, 1.25, 1.5, 2]
        playbackRate = supportedRates.contains(rate) ? rate : 1

        if player?.timeControlStatus == .playing {
            player?.rate = playbackRate
        }
    }

    public func clear() {
        player?.pause()
        removePeriodicObserver()
        statusObservation?.invalidate()
        statusObservation = nil
        player = nil
        currentURL = nil
        errorMessage = nil
        playbackRate = 1
        currentTimeSeconds = 0
        durationSeconds = nil
        isPlaying = false
        isAudioOnly = false
    }

    public func refreshSnapshot() {
        guard let player else {
            currentTimeSeconds = 0
            durationSeconds = nil
            isPlaying = false
            return
        }

        currentTimeSeconds = player.currentTime().seconds
        isPlaying = player.timeControlStatus == .playing

        let duration = player.currentItem?.duration.seconds
        if let duration, duration.isFinite, duration > 0 {
            durationSeconds = duration
        }
    }

    private func installPeriodicObserver() {
        guard let player else {
            return
        }

        periodicTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 2),
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshSnapshot()
            }
        }
    }

    private func removePeriodicObserver() {
        if let periodicTimeObserver {
            player?.removeTimeObserver(periodicTimeObserver)
            self.periodicTimeObserver = nil
        }
    }
}

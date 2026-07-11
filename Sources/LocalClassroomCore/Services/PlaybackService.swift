import AVFoundation
import Foundation

@MainActor
public final class PlaybackService: ObservableObject {
    @Published public private(set) var player: AVPlayer?
    @Published public private(set) var currentURL: URL?
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var playbackRate: Float = 1
    @Published public private(set) var currentTimeSeconds: Double = 0
    @Published public private(set) var durationSeconds: Double?

    private var periodicTimeObserver: Any?

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

        let asset = AVURLAsset(url: standardizedURL)
        let item = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: item)
        currentURL = standardizedURL
        errorMessage = nil
        playbackRate = 1
        currentTimeSeconds = 0
        durationSeconds = nil
        installPeriodicObserver()
    }

    public func play() {
        player?.playImmediately(atRate: playbackRate)
    }

    public func pause() {
        player?.pause()
    }

    public func seek(to seconds: Double) {
        player?.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600))
    }

    public func resume(to seconds: Double) {
        seek(to: seconds)
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
        player = nil
        currentURL = nil
        errorMessage = nil
        playbackRate = 1
        currentTimeSeconds = 0
        durationSeconds = nil
    }

    public func refreshSnapshot() {
        guard let player else {
            currentTimeSeconds = 0
            durationSeconds = nil
            return
        }

        currentTimeSeconds = player.currentTime().seconds

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

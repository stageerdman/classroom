import ClassroomCore
import SwiftUI

/// Button that shows the current playback speed (e.g. "1.5x") and opens a
/// popover with a drag-to-set slider, ranging from 1x to
/// `PlaybackService.maxPlaybackRate` in `PlaybackService.playbackRateStep`
/// increments. Speedup only — no slow-motion — per the product ask.
struct PlaybackSpeedControlView: View {
    @ObservedObject var playbackService: PlaybackService
    var tintColor: Color = .primary

    @State private var isShowingPopover = false

    var body: some View {
        Button {
            isShowingPopover = true
        } label: {
            Text(speedLabel)
                .monospacedDigit()
                .frame(minWidth: 34)
        }
        .help("Playback Speed")
        .popover(isPresented: $isShowingPopover, arrowEdge: .bottom) {
            speedSlider
        }
    }

    private var speedSlider: some View {
        VStack(spacing: 8) {
            Text(speedLabel)
                .font(.headline)
                .monospacedDigit()

            Slider(
                value: Binding(
                    get: { Double(playbackService.playbackRate) },
                    set: { playbackService.setPlaybackRate(Float($0)) }
                ),
                in: Double(PlaybackService.minPlaybackRate)...Double(PlaybackService.maxPlaybackRate),
                step: Double(PlaybackService.playbackRateStep)
            )
            .frame(width: 160)
        }
        .padding(12)
    }

    private var speedLabel: String {
        let rate = playbackService.playbackRate
        let formatted = rate.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", rate)
            : String(format: "%.2f", rate).trimmingTrailingZero()
        return "\(formatted)x"
    }
}

private extension String {
    /// Drops a single trailing zero left over from `%.2f` on values like
    /// "1.50" (from the .5 step) so it reads as "1.5" instead.
    func trimmingTrailingZero() -> String {
        hasSuffix("0") ? String(dropLast()) : self
    }
}

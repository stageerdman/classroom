import AppKit
import ClassroomCore
import SwiftUI

/// Custom progress/scrub bar: drag anywhere along it to seek, hover to
/// preview the exact timestamp and nearest cached thumbnail before
/// committing to a seek — AVKit's built-in scrubber supports neither on
/// macOS.
struct ScrubberView: View {
    let currentTime: Double
    let duration: Double
    let thumbnailProvider: ScrubThumbnailProvider
    let imageForFrame: (ThumbnailFrame) -> NSImage?
    let tintColor: Color
    let onScrub: (Double) -> Void
    let onScrubEnded: (Double) -> Void

    @State private var hoverX: CGFloat?
    @State private var isDragging = false

    private static let popoverWidth: CGFloat = 160
    private static let trackHeight: CGFloat = 4
    private static let knobDiameter: CGFloat = 10

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let progress = duration > 0 ? min(max(currentTime / duration, 0), 1) : 0

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(tintColor.opacity(0.25))
                    .frame(height: Self.trackHeight)

                Capsule()
                    .fill(tintColor)
                    .frame(width: width * progress, height: Self.trackHeight)

                Circle()
                    .fill(tintColor)
                    .frame(width: Self.knobDiameter, height: Self.knobDiameter)
                    .offset(x: max(0, width * progress - Self.knobDiameter / 2))
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(dragGesture(width: width))
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoverX = min(max(0, location.x), width)
                case .ended:
                    if !isDragging {
                        hoverX = nil
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                if let hoverX, duration > 0 {
                    let hoverTime = duration * (hoverX / width)
                    ScrubPreviewPopover(
                        time: hoverTime,
                        image: thumbnailProvider.nearestFrame(to: hoverTime).flatMap(imageForFrame)
                    )
                    .offset(x: popoverOffsetX(for: hoverX, containerWidth: width), y: -110)
                }
            }
        }
        .frame(height: 16)
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard duration > 0 else { return }
                isDragging = true
                let x = min(max(0, value.location.x), width)
                hoverX = x
                onScrub(duration * (x / width))
            }
            .onEnded { value in
                guard duration > 0 else { return }
                let x = min(max(0, value.location.x), width)
                onScrubEnded(duration * (x / width))
                isDragging = false
            }
    }

    private func popoverOffsetX(for hoverX: CGFloat, containerWidth: CGFloat) -> CGFloat {
        let half = Self.popoverWidth / 2
        return min(max(hoverX - half, 0), max(0, containerWidth - Self.popoverWidth))
    }
}

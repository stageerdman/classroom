import AppKit
import ClassroomCore
import SwiftUI

/// The small YouTube-style card shown above the scrubber while hovering:
/// a cached thumbnail (if one's been generated near this time yet) plus
/// the exact timestamp under the cursor.
struct ScrubPreviewPopover: View {
    let time: Double
    let image: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 160, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Text(formatPlaybackTime(time))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .padding(6)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
        .fixedSize()
        .allowsHitTesting(false)
    }
}

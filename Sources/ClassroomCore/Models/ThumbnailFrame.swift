import Foundation

/// A single cached scrub-preview frame — the small thumbnail image shown
/// when hovering the video progress bar, paired with the timestamp it was
/// captured at.
public struct ThumbnailFrame: Equatable {
    public let time: Double
    public let imageURL: URL

    public init(time: Double, imageURL: URL) {
        self.time = time
        self.imageURL = imageURL
    }
}

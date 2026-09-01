import Foundation

/// Owns the lifecycle of scrub-preview thumbnail generation for whichever
/// lesson is currently loaded, so the transport bar can look up the
/// nearest thumbnail to a hovered time without blocking on generation.
@MainActor
public final class ScrubThumbnailProvider: ObservableObject {
    @Published public private(set) var frames: [ThumbnailFrame] = []

    private let service: ThumbnailService
    private var currentTask: Task<Void, Never>?
    private var currentKey: String?

    public init(service: ThumbnailService = ThumbnailService()) {
        self.service = service
    }

    public func load(mediaURL: URL, classroomRootURL: URL, lessonRelativePath: String) {
        let key = "\(lessonRelativePath)|\(mediaURL.path)"
        guard key != currentKey else {
            return
        }

        currentTask?.cancel()
        currentKey = key
        frames = []

        let service = service
        currentTask = Task { [weak self] in
            guard let result = try? await service.thumbnails(
                forMediaAt: mediaURL,
                classroomRootURL: classroomRootURL,
                lessonRelativePath: lessonRelativePath
            ) else {
                return
            }

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                guard self?.currentKey == key else { return }
                self?.frames = result
            }
        }
    }

    public func clear() {
        currentTask?.cancel()
        currentTask = nil
        currentKey = nil
        frames = []
    }

    public func nearestFrame(to time: Double) -> ThumbnailFrame? {
        frames.min { abs($0.time - time) < abs($1.time - time) }
    }
}

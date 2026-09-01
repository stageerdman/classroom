import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Generates and caches a sparse set of scrub-preview thumbnails for a
/// lesson's video, YouTube-style. Thumbnails are generated once (on lesson
/// load) rather than per-hover, and cached to disk under the classroom's
/// `.classroom` metadata directory so reopening a lesson doesn't
/// regenerate them.
/// `FileManager` isn't formally `Sendable`, but the instance methods used
/// here (attribute reads, directory/file creation) are documented as
/// thread-safe, so `@unchecked` is safe — this lets the service be called
/// from a background `Task` without hopping back to the caller's actor.
public struct ThumbnailService: @unchecked Sendable {
    public static let cacheDirectoryName = "thumbnails"

    private static let defaultInterval: Double = 10
    private static let maxFrameCount = 60
    private static let thumbnailMaxWidth: CGFloat = 240
    private static let manifestFileName = "manifest.json"

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public enum ThumbnailServiceError: Error {
        case encodingFailed
    }

    /// Returns cached thumbnails for `mediaURL` if the source file hasn't
    /// changed since they were generated, otherwise regenerates them.
    public func thumbnails(
        forMediaAt mediaURL: URL,
        classroomRootURL: URL,
        lessonRelativePath: String
    ) async throws -> [ThumbnailFrame] {
        let asset = AVURLAsset(url: mediaURL)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else {
            return []
        }

        let cacheDirectory = cacheDirectoryURL(classroomRootURL: classroomRootURL, lessonRelativePath: lessonRelativePath)
        let signature = try sourceSignature(of: mediaURL)

        if let cachedManifest = try? loadManifest(at: cacheDirectory), cachedManifest.signature == signature {
            return cachedManifest.frames.map {
                ThumbnailFrame(time: $0.time, imageURL: cacheDirectory.appendingPathComponent($0.fileName))
            }
        }

        try? fileManager.removeItem(at: cacheDirectory)
        try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: Self.thumbnailMaxWidth, height: 0)

        var frames: [ThumbnailFrame] = []
        var manifestFrames: [ThumbnailManifest.Frame] = []

        for time in Self.sampleTimes(duration: duration) {
            guard let result = try? await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)) else {
                continue
            }

            let fileName = "\(Int(time.rounded())).jpg"
            let fileURL = cacheDirectory.appendingPathComponent(fileName)

            do {
                try writeJPEG(result.image, to: fileURL)
            } catch {
                continue
            }

            frames.append(ThumbnailFrame(time: time, imageURL: fileURL))
            manifestFrames.append(ThumbnailManifest.Frame(time: time, fileName: fileName))
        }

        let manifest = ThumbnailManifest(signature: signature, frames: manifestFrames)
        try? saveManifest(manifest, at: cacheDirectory)

        return frames
    }

    static func sampleTimes(duration: Double, interval: Double = defaultInterval, maxCount: Int = maxFrameCount) -> [Double] {
        guard duration > 0 else {
            return []
        }

        let count = min(maxCount, max(4, Int((duration / interval).rounded(.up))))
        let step = duration / Double(count)
        return (0..<count).map { Double($0) * step }
    }

    private func cacheDirectoryURL(classroomRootURL: URL, lessonRelativePath: String) -> URL {
        let sanitized = lessonRelativePath.replacingOccurrences(of: "/", with: "__")
        return classroomRootURL
            .appendingPathComponent(MetadataStore.metadataDirectoryName, isDirectory: true)
            .appendingPathComponent(Self.cacheDirectoryName, isDirectory: true)
            .appendingPathComponent(sanitized, isDirectory: true)
    }

    private func sourceSignature(of mediaURL: URL) throws -> ThumbnailManifest.SourceSignature {
        let attributes = try fileManager.attributesOfItem(atPath: mediaURL.path)
        let size = attributes[.size] as? Int ?? 0
        let modifiedAt = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return ThumbnailManifest.SourceSignature(size: size, modifiedAt: modifiedAt)
    }

    private func loadManifest(at directory: URL) throws -> ThumbnailManifest {
        let data = try Data(contentsOf: directory.appendingPathComponent(Self.manifestFileName))
        return try JSONDecoder().decode(ThumbnailManifest.self, from: data)
    }

    private func saveManifest(_ manifest: ThumbnailManifest, at directory: URL) throws {
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: directory.appendingPathComponent(Self.manifestFileName), options: [.atomic])
    }

    private func writeJPEG(_ image: CGImage, to url: URL, quality: CGFloat = 0.6) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ThumbnailServiceError.encodingFailed
        }

        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw ThumbnailServiceError.encodingFailed
        }
    }
}

private struct ThumbnailManifest: Codable {
    struct SourceSignature: Codable, Equatable {
        let size: Int
        let modifiedAt: TimeInterval
    }

    struct Frame: Codable {
        let time: Double
        let fileName: String
    }

    let signature: SourceSignature
    let frames: [Frame]
}

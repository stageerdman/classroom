import Foundation

/// One-time, self-healing migration for lessons that predate the Page/Notes
/// split: their single arbitrary `.md` file was, in practice, always
/// authored lesson content (rendered under the old single "Notes" section),
/// never the viewer's personal notes. `ClassroomScanner` renames that file
/// in place to the new fixed `page.md` name the first time it's scanned
/// after the split, so it's recognized as Page content going forward.
struct PageMigrationService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Returns the resulting `page.md` URL: the migrated location on
    /// success, or `legacyCandidateURL` unchanged if the rename couldn't be
    /// performed (e.g. a read-only volume) — content is never lost either
    /// way, just left under its old name to try again next scan.
    func migrate(legacyCandidateURL: URL, pageFileName: String) -> URL {
        let destinationURL = legacyCandidateURL.deletingLastPathComponent().appendingPathComponent(pageFileName)

        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            return legacyCandidateURL
        }

        do {
            try fileManager.moveItem(at: legacyCandidateURL, to: destinationURL)
            return destinationURL
        } catch {
            return legacyCandidateURL
        }
    }
}

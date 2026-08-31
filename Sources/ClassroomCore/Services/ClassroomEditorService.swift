import Foundation

/// File-system operations backing the module editor. Pure filesystem
/// concerns only — callers (the editor view model) are responsible for
/// calling `MetadataStore.migratePath` after any operation that changes a
/// node's relative path, so playback/completion/order state follows it.
public struct ClassroomEditorService {
    public struct TransformCandidates: Equatable {
        public let mediaFiles: [URL]
        public let notesFiles: [URL]
        public let isAlreadyLesson: Bool
        public let hasSubfolders: Bool

        public var canTransform: Bool {
            !isAlreadyLesson && !hasSubfolders
        }
    }

    /// What a successful `transformToLesson` actually did to the folder —
    /// enough for a caller to undo it precisely: move the archived files
    /// back out of `Attachments/`, remove that folder if the transform is
    /// what created it, and remove the `.lesson` marker.
    public struct TransformResult: Equatable {
        public let archivedFileNames: [String]
        public let createdAttachmentsFolder: Bool
    }

    public enum EditorError: Error, Equatable {
        case emptyName
        case invalidCharacters
        case nameCollision
        case sourceMissing
        case alreadyALesson
        case hasSubfolders
    }

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: Transform

    public func transformCandidates(for folderURL: URL) -> TransformCandidates {
        let files = (try? looseFiles(in: folderURL)) ?? []
        let directories = (try? looseDirectories(in: folderURL)) ?? []
        let media = sortedByName(files.filter { ClassroomScanner.defaultMediaExtensions.contains($0.pathExtension.lowercased()) })
        let notes = sortedByName(files.filter { $0.pathExtension.lowercased() == "md" })

        // Only a subfolder that's itself a real lesson blocks the transform —
        // that's the signal this folder is genuinely functioning as a
        // Category. An "Attachments"/"Removed" folder or any other unmarked
        // subfolder is left alone (or, for Attachments/Removed, picked up by
        // the scanner as-is) and simply surfaces as a ghost afterward.
        let blockingSubfolders = directories.filter(isLessonFolder)

        return TransformCandidates(
            mediaFiles: media,
            notesFiles: notes,
            isAlreadyLesson: isLessonFolder(folderURL),
            hasSubfolders: !blockingSubfolders.isEmpty
        )
    }

    @discardableResult
    public func transformToLesson(_ folderURL: URL, chosenMedia: URL? = nil, chosenNotes: URL? = nil) throws -> TransformResult {
        let candidates = transformCandidates(for: folderURL)
        guard !candidates.isAlreadyLesson else {
            throw EditorError.alreadyALesson
        }
        guard !candidates.hasSubfolders else {
            throw EditorError.hasSubfolders
        }

        let attachmentsDir = attachmentsDirectory(for: folderURL)
        let attachmentsExistedBefore = fileManager.fileExists(atPath: attachmentsDir.path)

        try Data().write(to: folderURL.appendingPathComponent(ClassroomScanner.lessonMarkerFileName))

        let finalMedia = chosenMedia ?? (candidates.mediaFiles.count == 1 ? candidates.mediaFiles.first : nil)
        let finalNotes = chosenNotes ?? (candidates.notesFiles.count == 1 ? candidates.notesFiles.first : nil)
        let keep = Set([finalMedia, finalNotes].compactMap { $0?.standardizedFileURL.path })

        let toArchive = try looseFiles(in: folderURL).filter { !keep.contains($0.standardizedFileURL.path) }
        var archivedFileNames: [String] = []
        for file in toArchive {
            let archivedURL = try importFile(file, into: attachmentsDir)
            archivedFileNames.append(archivedURL.lastPathComponent)
        }

        return TransformResult(
            archivedFileNames: archivedFileNames,
            createdAttachmentsFolder: !attachmentsExistedBefore && !archivedFileNames.isEmpty
        )
    }

    /// Reverses a successful `transformToLesson`: moves the archived files
    /// back out of `Attachments/`, removes that folder if the transform
    /// created it, and removes the `.lesson` marker. Used by undo.
    public func undoTransformToLesson(_ folderURL: URL, result: TransformResult) throws {
        let attachmentsDir = attachmentsDirectory(for: folderURL)
        for name in result.archivedFileNames {
            let archivedURL = attachmentsDir.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: archivedURL.path) else {
                continue
            }
            _ = try move(archivedURL, into: folderURL)
        }

        if result.createdAttachmentsFolder {
            try? fileManager.removeItem(at: attachmentsDir)
        }

        try? fileManager.removeItem(at: folderURL.appendingPathComponent(ClassroomScanner.lessonMarkerFileName))
    }

    // MARK: Ghosts — everything on disk that isn't part of the recognized structure

    /// Every visible file/folder directly inside `folderURL` whose name
    /// isn't in `knownNames` — i.e. not already a recognized Lesson or
    /// Category. Used so the editor can show what exists on disk even
    /// before it's been folded into the structure.
    public func ghostEntries(in folderURL: URL, excludingNames knownNames: Set<String>) -> [GhostEntry] {
        let children = (try? visibleChildren(of: folderURL)) ?? []
        let ghosts = children.filter { !knownNames.contains($0.lastPathComponent) }

        return sortedByName(ghosts).map { url in
            GhostEntry(
                id: url.path,
                name: url.lastPathComponent,
                url: url,
                isDirectory: FileSystemVisibility.isDirectory(url)
            )
        }
    }

    /// Ghosts for inside a Lesson folder specifically — anything that isn't
    /// its chosen media file, its chosen notes file, or the `Attachments`/
    /// `Removed` folders (matched case-insensitively, same as the scanner).
    public func lessonGhostEntries(lessonFolderURL: URL, mediaURL: URL?, notesURL: URL?) -> [GhostEntry] {
        let children = (try? visibleChildren(of: lessonFolderURL)) ?? []
        let reservedPaths = Set([mediaURL, notesURL].compactMap { $0?.standardizedFileURL.path })

        let ghosts = children.filter { url in
            if reservedPaths.contains(url.standardizedFileURL.path) {
                return false
            }
            if FileSystemVisibility.isDirectory(url) {
                let lowerName = url.lastPathComponent.lowercased()
                if lowerName == ClassroomScanner.attachmentsFolderName || lowerName == ClassroomScanner.removedFolderName {
                    return false
                }
            }
            return true
        }

        return sortedByName(ghosts).map { url in
            GhostEntry(
                id: url.path,
                name: url.lastPathComponent,
                url: url,
                isDirectory: FileSystemVisibility.isDirectory(url)
            )
        }
    }

    // MARK: Create

    public func createCategory(in parentURL: URL, name: String) throws -> URL {
        try createFolder(in: parentURL, name: name, asLesson: false)
    }

    public func createLesson(in parentURL: URL, name: String) throws -> URL {
        try createFolder(in: parentURL, name: name, asLesson: true)
    }

    // MARK: Rename / move / trash

    public func rename(_ url: URL, to newName: String) throws -> URL {
        let validatedName = try validate(name: newName)
        let destinationURL = url.deletingLastPathComponent().appendingPathComponent(validatedName, isDirectory: true)

        guard destinationURL.standardizedFileURL.path != url.standardizedFileURL.path else {
            return url
        }
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw EditorError.nameCollision
        }

        try fileManager.moveItem(at: url, to: destinationURL)
        return destinationURL
    }

    public func move(_ url: URL, into destinationDirectory: URL) throws -> URL {
        let destinationURL = destinationDirectory.appendingPathComponent(url.lastPathComponent, isDirectory: true)

        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw EditorError.nameCollision
        }

        try fileManager.moveItem(at: url, to: destinationURL)
        return destinationURL
    }

    /// Returns the item's resulting location inside the Trash, so a caller
    /// (undo) can restore it later — macOS may rename it there to avoid a
    /// collision with something already in the Trash.
    @discardableResult
    public func trash(_ url: URL) throws -> URL {
        var resultingItemURL: NSURL?
        try fileManager.trashItem(at: url, resultingItemURL: &resultingItemURL)
        guard let trashedURL = resultingItemURL as URL? else {
            throw EditorError.sourceMissing
        }
        return trashedURL
    }

    /// Moves an item back out of the Trash to an exact destination path —
    /// used by undo, where the destination must match the original
    /// location precisely rather than being auto-disambiguated like
    /// `move(_:into:)` does.
    public func restore(_ trashedURL: URL, to destinationURL: URL) throws {
        guard fileManager.fileExists(atPath: trashedURL.path) else {
            throw EditorError.sourceMissing
        }
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw EditorError.nameCollision
        }
        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: trashedURL, to: destinationURL)
    }

    // MARK: Import (always a move, per the locked "Finder drag moves" decision)

    @discardableResult
    public func importFile(_ sourceURL: URL, into destinationDirectory: URL) throws -> URL {
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw EditorError.sourceMissing
        }

        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let destinationURL = availableDestinationURL(in: destinationDirectory, forDesiredName: sourceURL.lastPathComponent)
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    @discardableResult
    public func addAttachment(lessonFolderURL: URL, fileURL: URL) throws -> URL {
        try importFile(fileURL, into: attachmentsDirectory(for: lessonFolderURL))
    }

    public func removeAttachment(lessonFolderURL: URL, attachmentURL: URL) throws {
        _ = try importFile(attachmentURL, into: removedDirectory(for: lessonFolderURL))
    }

    public func replaceHeroMedia(lessonFolderURL: URL, newMediaURL: URL) throws {
        let existingMedia = try looseFiles(in: lessonFolderURL).filter {
            ClassroomScanner.defaultMediaExtensions.contains($0.pathExtension.lowercased())
        }
        for oldMedia in existingMedia {
            _ = try importFile(oldMedia, into: attachmentsDirectory(for: lessonFolderURL))
        }
        _ = try importFile(newMediaURL, into: lessonFolderURL)
    }

    public func notesLinkMarkdown(for fileURL: URL) -> String {
        "[\(fileURL.lastPathComponent)](\(fileURL.absoluteString))"
    }

    // MARK: Private helpers

    private func attachmentsDirectory(for lessonFolderURL: URL) -> URL {
        lessonFolderURL.appendingPathComponent(ClassroomScanner.attachmentsFolderDisplayName, isDirectory: true)
    }

    private func removedDirectory(for lessonFolderURL: URL) -> URL {
        lessonFolderURL.appendingPathComponent(ClassroomScanner.removedFolderDisplayName, isDirectory: true)
    }

    private func createFolder(in parentURL: URL, name: String, asLesson: Bool) throws -> URL {
        let validatedName = try validate(name: name)
        let destinationURL = parentURL.appendingPathComponent(validatedName, isDirectory: true)

        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw EditorError.nameCollision
        }

        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        if asLesson {
            try Data().write(to: destinationURL.appendingPathComponent(ClassroomScanner.lessonMarkerFileName))
        }
        return destinationURL
    }

    private func validate(name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw EditorError.emptyName
        }
        guard !trimmed.contains("/"), !trimmed.contains(":") else {
            throw EditorError.invalidCharacters
        }
        return trimmed
    }

    private func isLessonFolder(_ url: URL) -> Bool {
        fileManager.fileExists(atPath: url.appendingPathComponent(ClassroomScanner.lessonMarkerFileName).path)
    }

    private func looseFiles(in folderURL: URL) throws -> [URL] {
        try visibleChildren(of: folderURL).filter { FileSystemVisibility.isRegularFile($0) }
    }

    private func looseDirectories(in folderURL: URL) throws -> [URL] {
        try visibleChildren(of: folderURL).filter { FileSystemVisibility.isDirectory($0) }
    }

    private func visibleChildren(of folderURL: URL) throws -> [URL] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isHiddenKey, .isSymbolicLinkKey]
        let entries = try fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants]
        )
        return entries.filter { !FileSystemVisibility.isHidden($0) && !FileSystemVisibility.isSymbolicLink($0) }
    }

    private func sortedByName(_ urls: [URL]) -> [URL] {
        urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func availableDestinationURL(in directory: URL, forDesiredName desiredName: String) -> URL {
        let candidate = directory.appendingPathComponent(desiredName)
        guard fileManager.fileExists(atPath: candidate.path) else {
            return candidate
        }

        let ext = (desiredName as NSString).pathExtension
        let base = (desiredName as NSString).deletingPathExtension
        var counter = 2

        while true {
            let newName = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            let newCandidate = directory.appendingPathComponent(newName)
            if !fileManager.fileExists(atPath: newCandidate.path) {
                return newCandidate
            }
            counter += 1
        }
    }
}

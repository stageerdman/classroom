import Foundation

/// Scans a classroom root folder into an in-memory `Classroom` tree.
///
/// A folder is a Lesson if it directly contains the hidden
/// `lessonMarkerFileName` file. This lets a Lesson folder and a Category
/// folder coexist at the same depth without inspecting file contents to
/// tell them apart.
public struct ClassroomScanner {
    public static let lessonMarkerFileName = ".lesson"
    public static let attachmentsFolderName = "attachments"
    public static let removedFolderName = "removed"
    /// Canonical capitalization used when the editor creates these folders.
    public static let attachmentsFolderDisplayName = "Attachments"
    public static let removedFolderDisplayName = "Removed"
    public static let moduleDescriptionFileName = "description.md"
    /// What counts as a lesson's playable media on disk — not the same as
    /// what AVFoundation can actually *play*. `flv` in particular scans in
    /// here (so a lesson with only a `.flv` video isn't silently treated as
    /// having no media / dropped to a stray file) but macOS's AVFoundation
    /// has no FLV demuxer; `PlaybackService` detects that failure and
    /// surfaces a specific, actionable message rather than a silent dead
    /// player. See `PlaybackService.knownUnplayableContainerExtensions`.
    public static let defaultMediaExtensions: Set<String> = ["mp4", "mov", "m4v", "mp3", "m4a", "wav", "flv"]

    private let fileManager: FileManager
    private let supportedMediaExtensions: Set<String>

    public init(
        fileManager: FileManager = .default,
        supportedMediaExtensions: Set<String> = ClassroomScanner.defaultMediaExtensions
    ) {
        self.fileManager = fileManager
        self.supportedMediaExtensions = supportedMediaExtensions
    }

    public func scan(rootURL: URL) -> Classroom {
        let standardizedRoot = rootURL.standardizedFileURL
        let classroomName = standardizedRoot.lastPathComponent
        var warnings: [ClassroomWarning] = []

        guard directoryExists(at: standardizedRoot) else {
            warnings.append(
                ClassroomWarning(
                    kind: .rootMissing,
                    relativePath: "",
                    message: "Selected classroom folder does not exist."
                )
            )
            return Classroom(rootURL: standardizedRoot, name: classroomName, modules: [], warnings: warnings)
        }

        let moduleURLs = visibleDirectoryChildren(of: standardizedRoot, rootURL: standardizedRoot, warnings: &warnings)
        let modules = NaturalSort.sorted(moduleURLs.map { moduleURL in
            scanModule(moduleURL, rootURL: standardizedRoot, warnings: &warnings)
        }, by: \.name)

        return Classroom(rootURL: standardizedRoot, name: classroomName, modules: modules, warnings: warnings)
    }

    private func scanModule(_ moduleURL: URL, rootURL: URL, warnings: inout [ClassroomWarning]) -> ClassroomModule {
        let children = visibleChildren(of: moduleURL, rootURL: rootURL, warnings: &warnings)
        let fileChildren = children.filter { FileSystemVisibility.isRegularFile($0) }
        let directoryChildren = children.filter { FileSystemVisibility.isDirectory($0) }

        var directLessons: [Lesson] = []
        var categories: [LessonCategory] = []

        for childDirectory in directoryChildren {
            if isLessonFolder(childDirectory) {
                directLessons.append(scanLesson(childDirectory, rootURL: rootURL, warnings: &warnings))
            } else {
                categories.append(scanCategory(childDirectory, rootURL: rootURL, warnings: &warnings))
            }
        }

        return ClassroomModule(
            relativePath: relativePath(for: moduleURL, rootURL: rootURL),
            name: moduleURL.lastPathComponent,
            description: moduleDescription(fileChildren: fileChildren),
            directLessons: NaturalSort.sorted(directLessons, by: \.title),
            categories: NaturalSort.sorted(categories, by: \.name)
        )
    }

    private func scanCategory(_ categoryURL: URL, rootURL: URL, warnings: inout [ClassroomWarning]) -> LessonCategory {
        let directoryChildren = visibleDirectoryChildren(of: categoryURL, rootURL: rootURL, warnings: &warnings)
        var lessons: [Lesson] = []

        for childDirectory in directoryChildren {
            if isLessonFolder(childDirectory) {
                lessons.append(scanLesson(childDirectory, rootURL: rootURL, warnings: &warnings))
            } else {
                warnings.append(
                    ClassroomWarning(
                        kind: .unsupportedDepth,
                        relativePath: relativePath(for: childDirectory, rootURL: rootURL),
                        message: "Folders deeper than category level are only supported when marked as a lesson."
                    )
                )
            }
        }

        return LessonCategory(
            relativePath: relativePath(for: categoryURL, rootURL: rootURL),
            name: categoryURL.lastPathComponent,
            lessons: NaturalSort.sorted(lessons, by: \.title)
        )
    }

    private func scanLesson(_ lessonURL: URL, rootURL: URL, warnings: inout [ClassroomWarning]) -> Lesson {
        let children = visibleChildren(of: lessonURL, rootURL: rootURL, warnings: &warnings)
        let fileChildren = children.filter { FileSystemVisibility.isRegularFile($0) }
        let directoryChildren = children.filter { FileSystemVisibility.isDirectory($0) }
        let lessonRelativePath = relativePath(for: lessonURL, rootURL: rootURL)

        let mediaCandidates = sortedByFileName(
            fileChildren.filter { supportedMediaExtensions.contains($0.pathExtension.lowercased()) }
        )
        if mediaCandidates.count > 1 {
            warnings.append(
                ClassroomWarning(
                    kind: .ambiguousLessonMedia,
                    relativePath: lessonRelativePath,
                    message: "Multiple playable files found: \(mediaCandidates.map(\.lastPathComponent).joined(separator: ", ")). Using \(mediaCandidates[0].lastPathComponent)."
                )
            )
        }

        let notesCandidates = sortedByFileName(
            fileChildren.filter { $0.pathExtension.lowercased() == "md" }
        )
        if notesCandidates.count > 1 {
            warnings.append(
                ClassroomWarning(
                    kind: .ambiguousLessonNotes,
                    relativePath: lessonRelativePath,
                    message: "Multiple notes files found: \(notesCandidates.map(\.lastPathComponent).joined(separator: ", ")). Using \(notesCandidates[0].lastPathComponent)."
                )
            )
        }

        let attachmentsDirectory = directoryChildren.first {
            $0.lastPathComponent.lowercased() == Self.attachmentsFolderName
        }
        let attachmentURLs = attachmentsDirectory.map { attachmentsURL in
            sortedByFileName(
                visibleChildren(of: attachmentsURL, rootURL: rootURL, warnings: &warnings)
                    .filter { FileSystemVisibility.isRegularFile($0) }
            )
        } ?? []

        return Lesson(
            relativePath: lessonRelativePath,
            folderURL: lessonURL,
            mediaURL: mediaCandidates.first,
            notesURL: notesCandidates.first,
            attachmentURLs: attachmentURLs,
            title: lessonURL.lastPathComponent
        )
    }

    private func isLessonFolder(_ url: URL) -> Bool {
        fileManager.fileExists(atPath: url.appendingPathComponent(Self.lessonMarkerFileName).path)
    }

    private func moduleDescription(fileChildren: [URL]) -> String? {
        guard
            let descriptionURL = fileChildren.first(where: { $0.lastPathComponent.lowercased() == Self.moduleDescriptionFileName }),
            let text = try? String(contentsOf: descriptionURL, encoding: .utf8)
        else {
            return nil
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func sortedByFileName(_ urls: [URL]) -> [URL] {
        urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func visibleDirectoryChildren(
        of directoryURL: URL,
        rootURL: URL,
        warnings: inout [ClassroomWarning]
    ) -> [URL] {
        visibleChildren(of: directoryURL, rootURL: rootURL, warnings: &warnings).filter { childURL in
            FileSystemVisibility.isDirectory(childURL)
        }
    }

    private func visibleChildren(
        of directoryURL: URL,
        rootURL: URL,
        warnings: inout [ClassroomWarning]
    ) -> [URL] {
        do {
            let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isHiddenKey, .isSymbolicLinkKey]
            let children = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsPackageDescendants]
            )

            return children.filter { childURL in
                guard !FileSystemVisibility.isHidden(childURL) else {
                    return false
                }

                if FileSystemVisibility.isSymbolicLink(childURL) {
                    warnings.append(
                        ClassroomWarning(
                            kind: .symbolicLink,
                            relativePath: relativePath(for: childURL, rootURL: rootURL),
                            message: "Symbolic links are not supported."
                        )
                    )
                    return false
                }

                return true
            }
        } catch {
            warnings.append(
                ClassroomWarning(
                    kind: .unreadableDirectory,
                    relativePath: relativePath(for: directoryURL, rootURL: rootURL),
                    message: "Directory could not be read."
                )
            )
            return []
        }
    }

    private func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func relativePath(for url: URL, rootURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path

        guard path != rootPath, path.hasPrefix(rootPath + "/") else {
            return ""
        }

        return String(path.dropFirst(rootPath.count + 1))
    }
}

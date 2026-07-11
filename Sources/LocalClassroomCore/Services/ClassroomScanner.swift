import Foundation

public struct ClassroomScanner {
    private let fileManager: FileManager
    private let supportedVideoExtensions: Set<String>

    public init(
        fileManager: FileManager = .default,
        supportedVideoExtensions: Set<String> = ["mp4", "mov", "m4v"]
    ) {
        self.fileManager = fileManager
        self.supportedVideoExtensions = supportedVideoExtensions
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
        let directLessons = scanLessons(in: moduleURL, rootURL: rootURL, warnings: &warnings)
        let categoryURLs = visibleDirectoryChildren(of: moduleURL, rootURL: rootURL, warnings: &warnings)
        let categories = NaturalSort.sorted(categoryURLs.map { categoryURL in
            scanCategory(categoryURL, rootURL: rootURL, warnings: &warnings)
        }, by: \.name)

        return ClassroomModule(
            relativePath: relativePath(for: moduleURL, rootURL: rootURL),
            name: moduleURL.lastPathComponent,
            directLessons: directLessons,
            categories: categories
        )
    }

    private func scanCategory(_ categoryURL: URL, rootURL: URL, warnings: inout [ClassroomWarning]) -> LessonCategory {
        let nestedFolders = visibleDirectoryChildren(of: categoryURL, rootURL: rootURL, warnings: &warnings)
        for nestedFolder in nestedFolders {
            warnings.append(
                ClassroomWarning(
                    kind: .unsupportedDepth,
                    relativePath: relativePath(for: nestedFolder, rootURL: rootURL),
                    message: "Folders deeper than category level are not supported."
                )
            )
        }

        return LessonCategory(
            relativePath: relativePath(for: categoryURL, rootURL: rootURL),
            name: categoryURL.lastPathComponent,
            lessons: scanLessons(in: categoryURL, rootURL: rootURL, warnings: &warnings)
        )
    }

    private func scanLessons(in directoryURL: URL, rootURL: URL, warnings: inout [ClassroomWarning]) -> [Lesson] {
        let fileURLs = visibleFileChildren(of: directoryURL, rootURL: rootURL, warnings: &warnings)
        let videoURLs = fileURLs.filter { supportedVideoExtensions.contains($0.pathExtension.lowercased()) }
        appendDuplicateBasenameWarnings(for: videoURLs, rootURL: rootURL, warnings: &warnings)

        let lessons = videoURLs.map { videoURL in
            let title = videoURL.deletingPathExtension().lastPathComponent
            let notesURL = videoURL.deletingPathExtension().appendingPathExtension("md")

            return Lesson(
                relativePath: relativePath(for: videoURL, rootURL: rootURL),
                videoURL: videoURL,
                notesURL: notesURL,
                title: title,
                fileExtension: videoURL.pathExtension
            )
        }

        return NaturalSort.sorted(lessons, by: \.title)
    }

    private func visibleDirectoryChildren(
        of directoryURL: URL,
        rootURL: URL,
        warnings: inout [ClassroomWarning]
    ) -> [URL] {
        visibleChildren(of: directoryURL, rootURL: rootURL, warnings: &warnings).filter { childURL in
            resourceValue(for: childURL, keyPath: \.isDirectory) == true
        }
    }

    private func visibleFileChildren(
        of directoryURL: URL,
        rootURL: URL,
        warnings: inout [ClassroomWarning]
    ) -> [URL] {
        visibleChildren(of: directoryURL, rootURL: rootURL, warnings: &warnings).filter { childURL in
            resourceValue(for: childURL, keyPath: \.isRegularFile) == true
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
                guard !isHidden(childURL) else {
                    return false
                }

                if resourceValue(for: childURL, keyPath: \.isSymbolicLink) == true {
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

    private func appendDuplicateBasenameWarnings(
        for videoURLs: [URL],
        rootURL: URL,
        warnings: inout [ClassroomWarning]
    ) {
        let grouped = Dictionary(grouping: videoURLs) { videoURL in
            videoURL.deletingPathExtension().lastPathComponent.lowercased()
        }

        for duplicateURLs in grouped.values where duplicateURLs.count > 1 {
            let names = NaturalSort.sorted(duplicateURLs.map(\.lastPathComponent)).joined(separator: ", ")
            warnings.append(
                ClassroomWarning(
                    kind: .duplicateVideoBasename,
                    relativePath: relativePath(for: duplicateURLs[0].deletingLastPathComponent(), rootURL: rootURL),
                    message: "Duplicate video basenames found: \(names)."
                )
            )
        }
    }

    private func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func isHidden(_ url: URL) -> Bool {
        url.lastPathComponent.hasPrefix(".") || resourceValue(for: url, keyPath: \.isHidden) == true
    }

    private func resourceValue<T>(for url: URL, keyPath: KeyPath<URLResourceValues, T?>) -> T? {
        try? url.resourceValues(forKeys: [
            .isDirectoryKey,
            .isRegularFileKey,
            .isHiddenKey,
            .isSymbolicLinkKey
        ])[keyPath: keyPath]
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

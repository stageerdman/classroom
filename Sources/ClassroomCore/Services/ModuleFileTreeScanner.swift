import Foundation

/// Builds the editor's raw file tree for one module folder — everything
/// visible on disk, unfiltered by classroom semantics, so the editor can
/// show (and act on) files and folders the normal `ClassroomScanner`
/// doesn't recognize.
public struct ModuleFileTreeScanner {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func scan(moduleURL: URL, rootURL: URL) -> [FileNode] {
        children(of: moduleURL, rootURL: rootURL, insideLesson: false)
    }

    private func children(of directoryURL: URL, rootURL: URL, insideLesson: Bool) -> [FileNode] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isHiddenKey, .isSymbolicLinkKey]
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        let visible = entries.filter {
            !FileSystemVisibility.isHidden($0) && !FileSystemVisibility.isSymbolicLink($0)
        }

        let nodes = visible.map { url -> FileNode in
            let isDirectory = FileSystemVisibility.isDirectory(url)
            let isLesson = isDirectory && isLessonFolder(url)
            let structuralKind: ClassroomNodeKind? = {
                guard !insideLesson else { return nil }
                if isLesson { return .lesson }
                if isDirectory { return .category }
                return nil
            }()

            return FileNode(
                id: relativePath(for: url, rootURL: rootURL),
                url: url,
                name: url.lastPathComponent,
                isDirectory: isDirectory,
                isLessonFolder: isLesson,
                structuralKind: structuralKind,
                children: isDirectory
                    ? children(of: url, rootURL: rootURL, insideLesson: insideLesson || isLesson)
                    : []
            )
        }

        return NaturalSort.sorted(nodes, by: \.name)
    }

    private func isLessonFolder(_ url: URL) -> Bool {
        fileManager.fileExists(atPath: url.appendingPathComponent(ClassroomScanner.lessonMarkerFileName).path)
    }

    private func relativePath(for url: URL, rootURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path

        guard path != rootPath, path.hasPrefix(rootPath + "/") else {
            return url.lastPathComponent
        }

        return String(path.dropFirst(rootPath.count + 1))
    }
}

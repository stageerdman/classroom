import Foundation

/// Shared filesystem visibility rules used by anything that walks a
/// classroom folder tree — hidden files/folders (dotfiles or the Finder
/// hidden flag) are never shown to the user, in the normal scanner or in
/// the editor's raw file tree.
enum FileSystemVisibility {
    static func isHidden(_ url: URL) -> Bool {
        url.lastPathComponent.hasPrefix(".") || resourceValue(for: url, keyPath: \.isHidden) == true
    }

    static func isDirectory(_ url: URL) -> Bool {
        resourceValue(for: url, keyPath: \.isDirectory) == true
    }

    static func isRegularFile(_ url: URL) -> Bool {
        resourceValue(for: url, keyPath: \.isRegularFile) == true
    }

    static func isSymbolicLink(_ url: URL) -> Bool {
        resourceValue(for: url, keyPath: \.isSymbolicLink) == true
    }

    private static func resourceValue<T>(for url: URL, keyPath: KeyPath<URLResourceValues, T?>) -> T? {
        try? url.resourceValues(forKeys: [
            .isDirectoryKey,
            .isRegularFileKey,
            .isHiddenKey,
            .isSymbolicLinkKey
        ])[keyPath: keyPath]
    }
}

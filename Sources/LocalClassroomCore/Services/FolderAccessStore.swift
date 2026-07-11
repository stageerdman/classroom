import Foundation

public protocol FolderAccessStore {
    func saveAccess(for url: URL)
    func resolvedURL(forPath path: String) -> URL
}

public struct SecurityScopedFolderAccessStore: FolderAccessStore {
    private let userDefaults: UserDefaults
    private let keyPrefix = "folderBookmark."

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func saveAccess(for url: URL) {
        #if os(macOS)
        if let bookmarkData = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            userDefaults.set(bookmarkData, forKey: keyPrefix + url.standardizedFileURL.path)
        }
        #endif
    }

    public func resolvedURL(forPath path: String) -> URL {
        let fallbackURL = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL

        #if os(macOS)
        guard let bookmarkData = userDefaults.data(forKey: keyPrefix + fallbackURL.path) else {
            return fallbackURL
        }

        var isStale = false
        if let resolvedURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            if isStale {
                saveAccess(for: resolvedURL)
            }
            return resolvedURL.standardizedFileURL
        }
        #endif

        return fallbackURL
    }
}

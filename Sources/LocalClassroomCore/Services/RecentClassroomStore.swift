import Foundation

public struct RecentClassroomStore {
    private let userDefaults: UserDefaults
    private let key: String
    private let limit: Int

    public init(
        userDefaults: UserDefaults = .standard,
        key: String = "recentClassroomPaths",
        limit: Int = 10
    ) {
        self.userDefaults = userDefaults
        self.key = key
        self.limit = limit
    }

    public func list() -> [RecentClassroom] {
        paths().map(RecentClassroom.init(path:))
    }

    public func add(_ url: URL) {
        let path = url.standardizedFileURL.path
        var updated = paths().filter { $0 != path }
        updated.insert(path, at: 0)

        if updated.count > limit {
            updated = Array(updated.prefix(limit))
        }

        userDefaults.set(updated, forKey: key)
    }

    public func remove(path: String) {
        let standardizedPath = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
        userDefaults.set(paths().filter { $0 != standardizedPath }, forKey: key)
    }

    public func removeAll() {
        userDefaults.removeObject(forKey: key)
    }

    private func paths() -> [String] {
        userDefaults.stringArray(forKey: key) ?? []
    }
}

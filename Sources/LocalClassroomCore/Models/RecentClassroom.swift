import Foundation

public struct RecentClassroom: Identifiable, Equatable {
    public let path: String

    public init(path: String) {
        self.path = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
    }

    public var id: String {
        path
    }

    public var name: String {
        URL(fileURLWithPath: path, isDirectory: true).lastPathComponent
    }

    public var url: URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }
}

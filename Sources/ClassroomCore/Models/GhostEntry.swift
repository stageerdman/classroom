import Foundation

/// A file or folder that exists on disk inside a Module or Category but
/// doesn't correspond to a recognized Lesson or Category — shown in the
/// editor as a "ghost" so nothing on disk is invisible while reorganizing,
/// even before it's been folded into the structure.
public struct GhostEntry: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let url: URL
    public let isDirectory: Bool

    public init(id: String, name: String, url: URL, isDirectory: Bool) {
        self.id = id
        self.name = name
        self.url = url
        self.isDirectory = isDirectory
    }
}

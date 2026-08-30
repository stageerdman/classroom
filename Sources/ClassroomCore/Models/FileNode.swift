import Foundation

/// A node in the editor's raw filesystem tree for one module — every
/// visible file/folder, including ones the normal scanner treats as opaque
/// (`Attachments/`, `Removed/`). The `.lesson` marker file itself is never
/// surfaced as a node; its presence is exposed instead via
/// `isLessonFolder`.
public struct FileNode: Identifiable, Equatable {
    public let id: String
    public let url: URL
    public let name: String
    public let isDirectory: Bool
    public let isLessonFolder: Bool
    /// `.category`/`.lesson` if this node is part of the tracked classroom
    /// structure (eligible for metadata migration on rename/move); `nil`
    /// for anything else — loose files, and anything nested inside a
    /// lesson folder (`Attachments/`, `Removed/`, or an untransformed
    /// loose subfolder), none of which are ever tracked in metadata.
    public let structuralKind: ClassroomNodeKind?
    public var children: [FileNode]

    public init(
        id: String,
        url: URL,
        name: String,
        isDirectory: Bool,
        isLessonFolder: Bool,
        structuralKind: ClassroomNodeKind?,
        children: [FileNode] = []
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.isLessonFolder = isLessonFolder
        self.structuralKind = structuralKind
        self.children = children
    }
}

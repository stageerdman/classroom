import Foundation

public struct ClassroomMetadata: Codable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var moduleOrder: [String]
    public var categoryOrder: [String: [String]]
    public var lessonOrder: [String: [String]]
    public var lessonState: [String: LessonState]

    public init(
        schemaVersion: Int = ClassroomMetadata.currentSchemaVersion,
        moduleOrder: [String] = [],
        categoryOrder: [String: [String]] = [:],
        lessonOrder: [String: [String]] = [:],
        lessonState: [String: LessonState] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.moduleOrder = moduleOrder
        self.categoryOrder = categoryOrder
        self.lessonOrder = lessonOrder
        self.lessonState = lessonState
    }
}

public struct MetadataMergeResult: Equatable {
    public var classroom: Classroom
    public var metadata: ClassroomMetadata
    public var warnings: [ClassroomWarning]

    public init(classroom: Classroom, metadata: ClassroomMetadata, warnings: [ClassroomWarning]) {
        self.classroom = classroom
        self.metadata = metadata
        self.warnings = warnings
    }
}

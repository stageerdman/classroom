import Foundation

public struct Classroom: Equatable {
    public let rootURL: URL
    public let name: String
    public var modules: [ClassroomModule]
    public var warnings: [ClassroomWarning]

    public init(rootURL: URL, name: String, modules: [ClassroomModule], warnings: [ClassroomWarning]) {
        self.rootURL = rootURL
        self.name = name
        self.modules = modules
        self.warnings = warnings
    }
}

public struct ClassroomModule: Equatable {
    public let relativePath: String
    public var name: String
    public var directLessons: [Lesson]
    public var categories: [LessonCategory]

    public init(relativePath: String, name: String, directLessons: [Lesson], categories: [LessonCategory]) {
        self.relativePath = relativePath
        self.name = name
        self.directLessons = directLessons
        self.categories = categories
    }
}

public struct LessonCategory: Equatable {
    public let relativePath: String
    public var name: String
    public var lessons: [Lesson]

    public init(relativePath: String, name: String, lessons: [Lesson]) {
        self.relativePath = relativePath
        self.name = name
        self.lessons = lessons
    }
}

public struct Lesson: Equatable {
    public let relativePath: String
    public let videoURL: URL
    public let notesURL: URL
    public let title: String
    public let fileExtension: String
    public var state: LessonState

    public init(
        relativePath: String,
        videoURL: URL,
        notesURL: URL,
        title: String,
        fileExtension: String,
        state: LessonState = LessonState()
    ) {
        self.relativePath = relativePath
        self.videoURL = videoURL
        self.notesURL = notesURL
        self.title = title
        self.fileExtension = fileExtension
        self.state = state
    }
}

public struct LessonState: Codable, Equatable {
    public var playbackPositionSeconds: Double
    public var completed: Bool
    public var lastOpenedAt: Date?
    public var missingSince: Date?
    public var completionOverride: CompletionOverride?

    public init(
        playbackPositionSeconds: Double = 0,
        completed: Bool = false,
        lastOpenedAt: Date? = nil,
        missingSince: Date? = nil,
        completionOverride: CompletionOverride? = nil
    ) {
        self.playbackPositionSeconds = playbackPositionSeconds
        self.completed = completed
        self.lastOpenedAt = lastOpenedAt
        self.missingSince = missingSince
        self.completionOverride = completionOverride
    }
}

public enum CompletionOverride: String, Codable, Equatable {
    case completed
    case incomplete
}

public struct ClassroomWarning: Equatable, CustomStringConvertible {
    public enum Kind: Equatable {
        case rootMissing
        case unreadableDirectory
        case unsupportedDepth
        case duplicateVideoBasename
        case symbolicLink
        case malformedMetadata
        case unsupportedMetadataSchema
        case metadataWriteFailed
    }

    public let kind: Kind
    public let relativePath: String
    public let message: String

    public init(kind: Kind, relativePath: String, message: String) {
        self.kind = kind
        self.relativePath = relativePath
        self.message = message
    }

    public var description: String {
        if relativePath.isEmpty {
            return message
        }

        return "\(relativePath): \(message)"
    }
}

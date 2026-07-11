public struct ClassroomSidebar: Equatable {
    public var title: String
    public var modules: [SidebarModule]
    public var warningCount: Int

    public init(title: String, modules: [SidebarModule], warningCount: Int) {
        self.title = title
        self.modules = modules
        self.warningCount = warningCount
    }
}

public struct SidebarModule: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let directLessons: [SidebarLesson]
    public let categories: [SidebarCategory]

    public init(id: String, name: String, directLessons: [SidebarLesson], categories: [SidebarCategory]) {
        self.id = id
        self.name = name
        self.directLessons = directLessons
        self.categories = categories
    }
}

public struct SidebarCategory: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let lessons: [SidebarLesson]

    public init(id: String, name: String, lessons: [SidebarLesson]) {
        self.id = id
        self.name = name
        self.lessons = lessons
    }
}

public struct SidebarLesson: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let relativePath: String

    public init(id: String, title: String, relativePath: String) {
        self.id = id
        self.title = title
        self.relativePath = relativePath
    }
}

public struct ProgressSummary: Equatable {
    public let completedLessons: Int
    public let totalLessons: Int

    public init(completedLessons: Int, totalLessons: Int) {
        self.completedLessons = completedLessons
        self.totalLessons = totalLessons
    }

    public var percentage: Double {
        guard totalLessons > 0 else {
            return 0
        }

        return Double(completedLessons) / Double(totalLessons)
    }

    public var percentageText: String {
        "\(Int((percentage * 100).rounded()))%"
    }
}

public struct ModuleProgressSummary: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let progress: ProgressSummary

    public init(id: String, name: String, progress: ProgressSummary) {
        self.id = id
        self.name = name
        self.progress = progress
    }
}

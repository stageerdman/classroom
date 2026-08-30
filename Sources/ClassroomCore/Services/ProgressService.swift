import Foundation

public enum ProgressService {
    public static func clampedPosition(_ position: Double, duration: Double?) -> Double {
        let finitePosition = position.isFinite ? position : 0
        let lowerBoundedPosition = max(0, finitePosition)

        guard let duration, duration.isFinite, duration > 0 else {
            return lowerBoundedPosition
        }

        return min(lowerBoundedPosition, duration)
    }

    public static func updatedState(
        from state: LessonState,
        position: Double,
        duration: Double?,
        now: Date = Date(),
        autoCompleteThreshold: Double = 0.9
    ) -> LessonState {
        var updated = state
        updated.playbackPositionSeconds = clampedPosition(position, duration: duration)
        updated.lastOpenedAt = now

        if updated.completionOverride == nil,
           let duration,
           duration.isFinite,
           duration > 0,
           updated.playbackPositionSeconds / duration >= autoCompleteThreshold {
            updated.completed = true
        }

        return updated
    }

    public static func manuallyCompleted(_ state: LessonState, completed: Bool) -> LessonState {
        var updated = state
        updated.completed = completed
        updated.completionOverride = completed ? .completed : .incomplete
        return updated
    }

    public static func classroomProgress(for classroom: Classroom) -> ProgressSummary {
        summary(for: classroom.lessons)
    }

    public static func moduleProgress(for classroom: Classroom) -> [ModuleProgressSummary] {
        classroom.modules.map { module in
            ModuleProgressSummary(
                id: module.relativePath,
                name: module.name,
                progress: summary(for: module.lessons)
            )
        }
    }

    private static func summary(for lessons: [Lesson]) -> ProgressSummary {
        ProgressSummary(
            completedLessons: lessons.filter(\.state.completed).count,
            totalLessons: lessons.count
        )
    }
}

public extension Classroom {
    var lessons: [Lesson] {
        modules.flatMap(\.lessons)
    }
}

public extension ClassroomModule {
    var lessons: [Lesson] {
        directLessons + categories.flatMap(\.lessons)
    }
}

import Foundation

public struct MetadataStore {
    public static let metadataDirectoryName = ".local-classroom"
    public static let metadataFileName = "classroom.json"

    private let fileManager: FileManager
    private let calendar: Calendar

    public init(fileManager: FileManager = .default, calendar: Calendar = .current) {
        self.fileManager = fileManager
        self.calendar = calendar
    }

    public func loadMergeAndSave(
        classroom scannedClassroom: Classroom,
        now: Date = Date()
    ) -> MetadataMergeResult {
        var warnings: [ClassroomWarning] = []
        var metadata = loadOrCreateMetadata(rootURL: scannedClassroom.rootURL, now: now, warnings: &warnings)

        metadata = merge(metadata: metadata, with: scannedClassroom, now: now)
        metadata = cleanupOrphans(in: metadata, now: now)

        var mergedClassroom = applying(metadata: metadata, to: scannedClassroom)
        mergedClassroom.warnings.append(contentsOf: warnings)

        do {
            try save(metadata, rootURL: scannedClassroom.rootURL)
        } catch {
            let warning = ClassroomWarning(
                kind: .metadataWriteFailed,
                relativePath: Self.metadataRelativePath,
                message: "Metadata could not be saved."
            )
            mergedClassroom.warnings.append(warning)
            warnings.append(warning)
        }

        return MetadataMergeResult(classroom: mergedClassroom, metadata: metadata, warnings: warnings)
    }

    public func load(rootURL: URL) throws -> ClassroomMetadata {
        let data = try Data(contentsOf: metadataURL(rootURL: rootURL))
        let metadata = try decoder.decode(ClassroomMetadata.self, from: data)

        guard metadata.schemaVersion == ClassroomMetadata.currentSchemaVersion else {
            throw MetadataStoreError.unsupportedSchema(metadata.schemaVersion)
        }

        return metadata
    }

    public func save(_ metadata: ClassroomMetadata, rootURL: URL) throws {
        let directoryURL = metadataDirectoryURL(rootURL: rootURL)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let data = try encoder.encode(metadata)
        try data.write(to: metadataURL(rootURL: rootURL), options: [.atomic])
    }

    public func metadataURL(rootURL: URL) -> URL {
        metadataDirectoryURL(rootURL: rootURL).appendingPathComponent(Self.metadataFileName)
    }

    public func metadataDirectoryURL(rootURL: URL) -> URL {
        rootURL
            .appendingPathComponent(Self.metadataDirectoryName, isDirectory: true)
    }

    public func updateLessonState(
        rootURL: URL,
        relativePath: String,
        transform: (LessonState) -> LessonState
    ) throws -> LessonState {
        var metadata = try load(rootURL: rootURL)
        let currentState = metadata.lessonState[relativePath] ?? LessonState()
        let updatedState = transform(currentState)
        metadata.lessonState[relativePath] = updatedState
        try save(metadata, rootURL: rootURL)
        return updatedState
    }

    public func updateOrdering(rootURL: URL, transform: (inout ClassroomMetadata) -> Void) throws -> ClassroomMetadata {
        var metadata = try load(rootURL: rootURL)
        transform(&metadata)
        try save(metadata, rootURL: rootURL)
        return metadata
    }

    private func loadOrCreateMetadata(rootURL: URL, now: Date, warnings: inout [ClassroomWarning]) -> ClassroomMetadata {
        let url = metadataURL(rootURL: rootURL)

        guard fileManager.fileExists(atPath: url.path) else {
            return ClassroomMetadata()
        }

        do {
            return try load(rootURL: rootURL)
        } catch MetadataStoreError.unsupportedSchema(let schemaVersion) {
            backupMalformedMetadata(at: url, now: now)
            warnings.append(
                ClassroomWarning(
                    kind: .unsupportedMetadataSchema,
                    relativePath: Self.metadataRelativePath,
                    message: "Metadata schema version \(schemaVersion) is not supported. A backup was created and fresh metadata will be used."
                )
            )
            return ClassroomMetadata()
        } catch {
            backupMalformedMetadata(at: url, now: now)
            warnings.append(
                ClassroomWarning(
                    kind: .malformedMetadata,
                    relativePath: Self.metadataRelativePath,
                    message: "Metadata was malformed. A backup was created and fresh metadata will be used."
                )
            )
            return ClassroomMetadata()
        }
    }

    private func merge(metadata: ClassroomMetadata, with classroom: Classroom, now: Date) -> ClassroomMetadata {
        let visibleLessonPaths = Set(classroom.lessonRelativePaths)
        var merged = metadata

        for lessonPath in visibleLessonPaths {
            var state = merged.lessonState[lessonPath] ?? LessonState()
            state.missingSince = nil
            merged.lessonState[lessonPath] = state
        }

        for lessonPath in merged.lessonState.keys where !visibleLessonPaths.contains(lessonPath) {
            if merged.lessonState[lessonPath]?.missingSince == nil {
                merged.lessonState[lessonPath]?.missingSince = now
            }
        }

        merged.moduleOrder = merged.moduleOrder.filter { modulePath in
            classroom.modules.contains { $0.relativePath == modulePath }
        }

        for module in classroom.modules {
            let modulePath = module.relativePath
            merged.categoryOrder[modulePath] = (merged.categoryOrder[modulePath] ?? []).filter { categoryName in
                module.categories.contains { $0.name == categoryName }
            }
            merged.lessonOrder[modulePath] = (merged.lessonOrder[modulePath] ?? []).filter { lessonName in
                module.directLessons.contains { $0.relativePath.split(separator: "/").last.map(String.init) == lessonName }
            }

            for category in module.categories {
                merged.lessonOrder[category.relativePath] = (merged.lessonOrder[category.relativePath] ?? []).filter { lessonName in
                    category.lessons.contains { $0.relativePath.split(separator: "/").last.map(String.init) == lessonName }
                }
            }
        }

        return merged
    }

    private func cleanupOrphans(in metadata: ClassroomMetadata, now: Date) -> ClassroomMetadata {
        var cleaned = metadata
        let retentionStart = calendar.date(byAdding: .day, value: -30, to: now) ?? now

        cleaned.lessonState = cleaned.lessonState.filter { _, state in
            guard let missingSince = state.missingSince else {
                return true
            }

            return missingSince > retentionStart
        }

        return cleaned
    }

    private func applying(metadata: ClassroomMetadata, to classroom: Classroom) -> Classroom {
        var classroom = classroom

        classroom.modules = OrderingService.ordered(
            classroom.modules,
            savedOrder: metadata.moduleOrder,
            id: { $0.relativePath },
            naturalKey: { $0.name }
        )

        for moduleIndex in classroom.modules.indices {
            let modulePath = classroom.modules[moduleIndex].relativePath
            classroom.modules[moduleIndex].directLessons = OrderingService.ordered(
                classroom.modules[moduleIndex].directLessons,
                savedOrder: metadata.lessonOrder[modulePath] ?? [],
                id: { $0.fileName },
                naturalKey: { $0.title }
            )
            classroom.modules[moduleIndex].categories = OrderingService.ordered(
                classroom.modules[moduleIndex].categories,
                savedOrder: metadata.categoryOrder[modulePath] ?? [],
                id: { $0.name },
                naturalKey: { $0.name }
            )

            for lessonIndex in classroom.modules[moduleIndex].directLessons.indices {
                let relativePath = classroom.modules[moduleIndex].directLessons[lessonIndex].relativePath
                classroom.modules[moduleIndex].directLessons[lessonIndex].state = metadata.lessonState[relativePath] ?? LessonState()
            }

            for categoryIndex in classroom.modules[moduleIndex].categories.indices {
                let categoryPath = classroom.modules[moduleIndex].categories[categoryIndex].relativePath
                classroom.modules[moduleIndex].categories[categoryIndex].lessons = OrderingService.ordered(
                    classroom.modules[moduleIndex].categories[categoryIndex].lessons,
                    savedOrder: metadata.lessonOrder[categoryPath] ?? [],
                    id: { $0.fileName },
                    naturalKey: { $0.title }
                )

                for lessonIndex in classroom.modules[moduleIndex].categories[categoryIndex].lessons.indices {
                    let relativePath = classroom.modules[moduleIndex].categories[categoryIndex].lessons[lessonIndex].relativePath
                    classroom.modules[moduleIndex].categories[categoryIndex].lessons[lessonIndex].state = metadata.lessonState[relativePath] ?? LessonState()
                }
            }
        }

        return classroom
    }

    private func backupMalformedMetadata(at url: URL, now: Date) {
        let backupURL = url
            .deletingLastPathComponent()
            .appendingPathComponent("classroom.malformed-\(Self.backupTimestamp(for: now)).json")

        try? fileManager.moveItem(at: url, to: backupURL)
    }

    private static var metadataRelativePath: String {
        "\(metadataDirectoryName)/\(metadataFileName)"
    }

    private static func backupTimestamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public enum MetadataStoreError: Error, Equatable {
    case unsupportedSchema(Int)
}

private extension Classroom {
    var lessonRelativePaths: [String] {
        modules.flatMap { module in
            module.directLessons.map(\.relativePath) +
                module.categories.flatMap { $0.lessons.map(\.relativePath) }
        }
    }
}

private extension Lesson {
    var fileName: String {
        String(relativePath.split(separator: "/").last ?? "")
    }
}

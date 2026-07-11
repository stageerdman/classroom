import Foundation

public struct DeveloperScannerViewModel {
    private let scanner: ClassroomScanner

    public init(scanner: ClassroomScanner = ClassroomScanner()) {
        self.scanner = scanner
    }

    public func parseHierarchyText(path: String) -> String {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            return "Enter a classroom folder path."
        }

        let classroom = scanner.scan(rootURL: URL(fileURLWithPath: trimmedPath, isDirectory: true))
        return Self.hierarchyText(for: classroom)
    }

    public static func hierarchyText(for classroom: Classroom) -> String {
        var lines: [String] = ["Classroom: \(classroom.name)"]

        if classroom.modules.isEmpty {
            lines.append("No modules found.")
        }

        for module in classroom.modules {
            lines.append("Module: \(module.name)")

            for lesson in module.directLessons {
                lines.append("  Lesson: \(lesson.title).\(lesson.fileExtension)")
            }

            for category in module.categories {
                lines.append("  Category: \(category.name)")
                for lesson in category.lessons {
                    lines.append("    Lesson: \(lesson.title).\(lesson.fileExtension)")
                }
            }
        }

        if !classroom.warnings.isEmpty {
            lines.append("")
            lines.append("Warnings:")
            for warning in classroom.warnings {
                lines.append("- \(warning.description)")
            }
        }

        return lines.joined(separator: "\n")
    }
}

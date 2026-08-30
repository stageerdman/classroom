import ClassroomCore
import SwiftUI

/// Sidebar scoped to a single Module — shown after the user opens a module
/// from the classroom gallery. Reachable only from inside a module; the
/// classroom-wide view is `ClassroomGalleryView`.
struct ClassroomSidebarView: View {
    @ObservedObject var viewModel: ClassroomBrowserViewModel
    let module: SidebarModule
    @Binding var selectedSidebarID: String?
    let onSelectLesson: (SidebarLesson) -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            backButton

            List(selection: $selectedSidebarID) {
                Section(module.name) {
                    moduleProgressHeader

                    ForEach(module.directLessons) { lesson in
                        lessonRow(lesson)
                            .contextMenu {
                                Button("Move Up") {
                                    viewModel.moveDirectLesson(moduleID: module.id, lessonID: lesson.id, offset: -1)
                                }
                                Button("Move Down") {
                                    viewModel.moveDirectLesson(moduleID: module.id, lessonID: lesson.id, offset: 1)
                                }
                                Divider()
                                Button("Reset Direct Lesson Order") {
                                    viewModel.resetDirectLessonOrder(moduleID: module.id)
                                }
                            }
                    }
                    .onMove { source, destination in
                        viewModel.moveDirectLessons(moduleID: module.id, from: source, to: destination)
                    }

                    ForEach(module.categories) { category in
                        DisclosureGroup(category.name) {
                            ForEach(category.lessons) { lesson in
                                lessonRow(lesson)
                                    .contextMenu {
                                        Button("Move Up") {
                                            viewModel.moveCategoryLesson(categoryID: category.id, lessonID: lesson.id, offset: -1)
                                        }
                                        Button("Move Down") {
                                            viewModel.moveCategoryLesson(categoryID: category.id, lessonID: lesson.id, offset: 1)
                                        }
                                        Divider()
                                        Button("Reset Lesson Order") {
                                            viewModel.resetCategoryLessonOrder(categoryID: category.id)
                                        }
                                    }
                            }
                            .onMove { source, destination in
                                viewModel.moveCategoryLessons(categoryID: category.id, from: source, to: destination)
                            }
                        }
                        .contextMenu {
                            Button("Move Up") {
                                viewModel.moveCategory(moduleID: module.id, categoryID: category.id, offset: -1)
                            }
                            Button("Move Down") {
                                viewModel.moveCategory(moduleID: module.id, categoryID: category.id, offset: 1)
                            }
                            Divider()
                            Button("Reset Category Order") {
                                viewModel.resetCategoryOrder(moduleID: module.id)
                            }
                        }
                    }
                    .onMove { source, destination in
                        viewModel.moveCategories(moduleID: module.id, from: source, to: destination)
                    }
                }

                if let warningCount = viewModel.sidebar?.warningCount, warningCount > 0 {
                    Section("Warnings") {
                        Label("\(warningCount) structural warning\(warningCount == 1 ? "" : "s")", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(nsColor: .windowBackgroundColor))
            }
        }
    }

    private var backButton: some View {
        HStack {
            Button(action: onBack) {
                Label("Modules", systemImage: "chevron.left")
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(10)
    }

    private var moduleProgressHeader: some View {
        let progress = viewModel.moduleProgress.first { $0.id == module.id }?.progress
            ?? ProgressSummary(completedLessons: 0, totalLessons: 0)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Progress")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Text("\(progress.completedLessons)/\(progress.totalLessons) complete")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progress.percentage) {
                EmptyView()
            } currentValueLabel: {
                Text(progress.percentageText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func lessonRow(_ lesson: SidebarLesson) -> some View {
        HStack {
            lessonIcon(isCompleted: lesson.isCompleted)
            Text(lesson.title)
                .lineLimit(1)
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedSidebarID = lesson.id
            onSelectLesson(lesson)
        }
        .tag(lesson.id)
    }

    private func lessonIcon(isCompleted: Bool) -> some View {
        Image(systemName: isCompleted ? "checkmark.circle.fill" : "play.rectangle")
            .symbolRenderingMode(.monochrome)
            .foregroundColor(isCompleted ? Color(nsColor: .systemGreen) : Color.accentColor)
            .frame(width: 18, alignment: .center)
            .accessibilityHidden(true)
    }
}

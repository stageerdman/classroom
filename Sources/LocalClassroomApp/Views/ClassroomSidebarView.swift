import LocalClassroomCore
import SwiftUI

struct ClassroomSidebarView: View {
    @ObservedObject var viewModel: ClassroomBrowserViewModel
    @Binding var selectedSidebarID: String?
    let onSelectLesson: (SidebarLesson) -> Void

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedSidebarID) {
                if let sidebar = viewModel.sidebar {
                    Section(sidebar.title) {
                        progressHeader

                        ForEach(sidebar.modules) { module in
                            DisclosureGroup {
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
                            } label: {
                                Label(module.name, systemImage: "rectangle.stack")
                            }
                            .contextMenu {
                                Button("Move Up") {
                                    viewModel.moveModule(id: module.id, offset: -1)
                                }
                                Button("Move Down") {
                                    viewModel.moveModule(id: module.id, offset: 1)
                                }
                                Divider()
                                Button("Reset Module Order") {
                                    viewModel.resetModuleOrder()
                                }
                            }
                        }
                        .onMove { source, destination in
                            viewModel.moveModules(from: source, to: destination)
                        }
                    }

                    if sidebar.warningCount > 0 {
                        Section("Warnings") {
                            Label("\(sidebar.warningCount) structural warning\(sidebar.warningCount == 1 ? "" : "s")", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                } else {
                    Section("Classroom") {
                        Text("Open a folder to begin.")
                            .foregroundStyle(.secondary)
                    }
                }

                if !viewModel.recentClassrooms.isEmpty {
                    Section("Recent") {
                        ForEach(viewModel.recentClassrooms) { recent in
                            HStack {
                                Button {
                                    viewModel.openRecent(recent)
                                } label: {
                                    Label(recent.name, systemImage: "clock")
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)

                                Spacer()

                                Button {
                                    viewModel.removeRecent(recent)
                                } label: {
                                    Image(systemName: "xmark")
                                }
                                .buttonStyle(.borderless)
                                .help("Remove from recent classrooms")
                            }
                        }
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

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Progress")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Text("\(viewModel.classroomProgress.completedLessons)/\(viewModel.classroomProgress.totalLessons) complete")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: viewModel.classroomProgress.percentage) {
                EmptyView()
            } currentValueLabel: {
                Text(viewModel.classroomProgress.percentageText)
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

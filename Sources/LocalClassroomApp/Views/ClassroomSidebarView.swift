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
                                }

                                ForEach(module.categories) { category in
                                    DisclosureGroup(category.name) {
                                        ForEach(category.lessons) { lesson in
                                            lessonRow(lesson)
                                        }
                                    }
                                }
                            } label: {
                                Label(module.name, systemImage: "rectangle.stack")
                            }
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
            Label(lesson.title, systemImage: "play.rectangle")
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
}

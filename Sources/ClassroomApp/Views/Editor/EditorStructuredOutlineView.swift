import ClassroomCore
import SwiftUI

/// The Category/Lesson outline for the module being edited — reorder by
/// drag, reparent a lesson across categories by drag, create new items,
/// rename in place, and Trash whole items.
struct EditorStructuredOutlineView: View {
    @ObservedObject var viewModel: ClassroomEditorViewModel
    @Binding var selectedLessonID: String?
    @Binding var renameTarget: FileNode?
    @Binding var renameText: String

    @State private var isAddingDirectLesson = false
    @State private var newLessonName = ""
    @State private var isAddingCategory = false
    @State private var newCategoryName = ""

    var body: some View {
        List {
            Section {
                ForEach(viewModel.orderedDirectLessons) { lesson in
                    lessonRow(lesson)
                }
                .onMove { source, destination in
                    viewModel.moveDirectLessons(from: source, to: destination)
                }

                if isAddingDirectLesson {
                    newItemField(text: $newLessonName, placeholder: "New Lesson") {
                        viewModel.createLesson(name: newLessonName, in: nil)
                        newLessonName = ""
                        isAddingDirectLesson = false
                    }
                }
            } header: {
                sectionHeader(title: "Lessons") { isAddingDirectLesson = true }
            }
            .dropDestination(for: URL.self) { urls, _ in handleReparentDrop(urls, destination: nil) }

            Section {
                ForEach(viewModel.orderedCategories) { category in
                    categoryRow(category)
                }
                .onMove { source, destination in
                    viewModel.moveCategories(from: source, to: destination)
                }

                if isAddingCategory {
                    newItemField(text: $newCategoryName, placeholder: "New Category") {
                        viewModel.createCategory(name: newCategoryName, in: nil)
                        newCategoryName = ""
                        isAddingCategory = false
                    }
                }
            } header: {
                sectionHeader(title: "Categories") { isAddingCategory = true }
            }
        }
        .listStyle(.inset)
    }

    private func categoryRow(_ category: FileNode) -> some View {
        DisclosureGroup {
            ForEach(category.children.filter { $0.structuralKind == .lesson }) { lesson in
                lessonRow(lesson)
            }
            .onMove { source, destination in
                viewModel.moveCategoryLessons(category, from: source, to: destination)
            }
        } label: {
            itemLabel(category, systemImage: "rectangle.stack")
        }
        .dropDestination(for: URL.self) { urls, _ in handleReparentDrop(urls, destination: category) }
        .contextMenu { itemContextMenu(category) }
    }

    private func lessonRow(_ lesson: FileNode) -> some View {
        itemLabel(lesson, systemImage: lesson.isLessonFolder ? "play.rectangle" : "questionmark.folder")
            .contentShape(Rectangle())
            .background(selectedLessonID == lesson.id ? Color.accentColor.opacity(0.15) : Color.clear)
            .onTapGesture { selectedLessonID = lesson.id }
            .draggable(lesson.url)
            .contextMenu { itemContextMenu(lesson) }
    }

    @ViewBuilder
    private func itemLabel(_ node: FileNode, systemImage: String) -> some View {
        if renameTarget?.id == node.id {
            TextField("Name", text: $renameText, onCommit: { commitRename(node) })
                .textFieldStyle(.roundedBorder)
        } else {
            Label(node.name, systemImage: systemImage)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func itemContextMenu(_ node: FileNode) -> some View {
        Button("Rename") {
            renameTarget = node
            renameText = node.name
        }
        Button("Move to Trash", role: .destructive) {
            if selectedLessonID == node.id {
                selectedLessonID = nil
            }
            viewModel.trash(node)
        }
    }

    private func sectionHeader(title: String, onAdd: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button(action: onAdd) {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.plain)
        }
    }

    private func newItemField(text: Binding<String>, placeholder: String, onCommit: @escaping () -> Void) -> some View {
        TextField(placeholder, text: text, onCommit: onCommit)
            .textFieldStyle(.roundedBorder)
    }

    private func commitRename(_ node: FileNode) {
        guard renameTarget?.id == node.id else {
            return
        }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        renameTarget = nil
        guard !trimmed.isEmpty, trimmed != node.name else {
            return
        }
        viewModel.rename(node, to: trimmed)
    }

    private func handleReparentDrop(_ urls: [URL], destination: FileNode?) -> Bool {
        guard
            let url = urls.first,
            let node = viewModel.node(forURL: url),
            node.structuralKind == .lesson
        else {
            return false
        }

        viewModel.move(node, into: destination)
        return true
    }
}

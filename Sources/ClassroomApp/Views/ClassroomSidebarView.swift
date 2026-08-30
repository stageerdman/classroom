import ClassroomCore
import SwiftUI

/// Sidebar scoped to a single Module — shown after the user opens a module
/// from the classroom gallery. Reachable only from inside a module; the
/// classroom-wide view is `ClassroomGalleryView`.
///
/// When `viewModel.isEditingModule` is off this renders exactly as normal
/// browsing always has. Editing turns on inline rename, create, drag-to-
/// reparent, and Transform-to-Lesson directly on the same rows — there is
/// no separate editor screen.
struct ClassroomSidebarView: View {
    @ObservedObject var viewModel: ClassroomBrowserViewModel
    let module: SidebarModule
    @Binding var selectedSidebarID: String?
    let onSelectLesson: (SidebarLesson) -> Void
    let onBack: () -> Void

    @State private var editableModuleName = ""
    @State private var editableDescription = ""
    @State private var renameTargetID: String?
    @State private var renameText = ""
    @State private var isAddingDirectLesson = false
    @State private var newLessonName = ""
    @State private var isAddingCategory = false
    @State private var newCategoryName = ""
    @State private var addingLessonToCategoryID: String?
    @State private var newCategoryLessonName = ""

    var body: some View {
        VStack(spacing: 0) {
            backButton

            List(selection: $selectedSidebarID) {
                Section {
                    moduleProgressHeader

                    ForEach(module.directLessons) { lesson in
                        lessonRow(lesson)
                            .contextMenu { lessonContextMenu(lesson) }
                    }
                    .onMove { source, destination in
                        viewModel.moveDirectLessons(moduleID: module.id, from: source, to: destination)
                    }
                    .dropDestination(for: String.self) { ids, _ in
                        return handleReparentDrop(ids, categoryID: nil)
                    }

                    if viewModel.isEditingModule {
                        newItemRow(placeholder: "New Lesson", isAdding: $isAddingDirectLesson, text: $newLessonName) {
                            viewModel.createDirectLesson(name: newLessonName)
                            newLessonName = ""
                            isAddingDirectLesson = false
                        }
                    }

                    ForEach(module.categories) { category in
                        DisclosureGroup {
                            ForEach(category.lessons) { lesson in
                                lessonRow(lesson)
                                    .contextMenu { lessonContextMenu(lesson) }
                            }
                            .onMove { source, destination in
                                viewModel.moveCategoryLessons(categoryID: category.id, from: source, to: destination)
                            }

                            if viewModel.isEditingModule {
                                if addingLessonToCategoryID == category.id {
                                    TextField("New Lesson", text: $newCategoryLessonName, onCommit: {
                                        viewModel.createLesson(name: newCategoryLessonName, categoryID: category.id)
                                        newCategoryLessonName = ""
                                        addingLessonToCategoryID = nil
                                    })
                                    .textFieldStyle(.roundedBorder)
                                } else {
                                    Button {
                                        addingLessonToCategoryID = category.id
                                    } label: {
                                        Label("New Lesson", systemImage: "plus.circle")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } label: {
                            categoryLabel(category)
                        }
                        .contextMenu { categoryContextMenu(category) }
                        .dropDestination(for: String.self) { ids, _ in
                            return handleReparentDrop(ids, categoryID: category.id)
                        }
                    }
                    .onMove { source, destination in
                        viewModel.moveCategories(moduleID: module.id, from: source, to: destination)
                    }

                    if viewModel.isEditingModule {
                        newItemRow(placeholder: "New Category", isAdding: $isAddingCategory, text: $newCategoryName) {
                            viewModel.createCategory(name: newCategoryName)
                            newCategoryName = ""
                            isAddingCategory = false
                        }
                    }
                } header: {
                    sectionHeader
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
        .onAppear { syncEditableModuleFields() }
        .onChange(of: module.id) { _, _ in syncEditableModuleFields() }
        .sheet(item: Binding(
            get: { viewModel.pendingTransform },
            set: { if $0 == nil { viewModel.cancelPendingTransform() } }
        )) { pending in
            TransformDisambiguationSheet(pending: pending, viewModel: viewModel)
        }
    }

    private var backButton: some View {
        HStack {
            Button(action: onBack) {
                Label("Modules", systemImage: "chevron.left")
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                viewModel.setEditingModule(!viewModel.isEditingModule)
            } label: {
                Label(
                    viewModel.isEditingModule ? "Done" : "Edit",
                    systemImage: viewModel.isEditingModule ? "checkmark" : "pencil"
                )
            }
            .buttonStyle(.plain)
        }
        .padding(10)
    }

    @ViewBuilder
    private var sectionHeader: some View {
        if viewModel.isEditingModule {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Module Name", text: $editableModuleName, onCommit: commitModuleName)
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .foregroundStyle(.primary)

                TextField("Description shown on the gallery card (optional)", text: $editableDescription, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .lineLimit(1...3)
                    .onChange(of: editableDescription) { _, newValue in
                        viewModel.updateCurrentModuleDescription(newValue)
                    }
            }
            .padding(.vertical, 2)
            .textCase(nil)
        } else {
            Text(module.name)
        }
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

    @ViewBuilder
    private func lessonRow(_ lesson: SidebarLesson) -> some View {
        let row = HStack {
            lessonIcon(isCompleted: lesson.isCompleted)

            if viewModel.isEditingModule, renameTargetID == lesson.id {
                TextField("Name", text: $renameText, onCommit: { commitRename(lessonID: lesson.id) })
                    .textFieldStyle(.roundedBorder)
            } else {
                Text(lesson.title)
                    .lineLimit(1)
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard renameTargetID != lesson.id else { return }
            selectedSidebarID = lesson.id
            onSelectLesson(lesson)
        }
        .tag(lesson.id)

        if viewModel.isEditingModule {
            row.draggable(lesson.id)
        } else {
            row
        }
    }

    private func categoryLabel(_ category: SidebarCategory) -> some View {
        Group {
            if viewModel.isEditingModule, renameTargetID == category.id {
                TextField("Name", text: $renameText, onCommit: { commitRename(categoryID: category.id) })
                    .textFieldStyle(.roundedBorder)
            } else {
                Label(category.name, systemImage: "rectangle.stack")
            }
        }
    }

    @ViewBuilder
    private func lessonContextMenu(_ lesson: SidebarLesson) -> some View {
        Button("Move Up") { viewModel.moveDirectLesson(moduleID: module.id, lessonID: lesson.id, offset: -1) }
        Button("Move Down") { viewModel.moveDirectLesson(moduleID: module.id, lessonID: lesson.id, offset: 1) }
        Divider()
        Button("Reset Direct Lesson Order") { viewModel.resetDirectLessonOrder(moduleID: module.id) }

        if viewModel.isEditingModule {
            Divider()
            Button("Rename") {
                renameTargetID = lesson.id
                renameText = lesson.title
            }
            Button("Move to Trash", role: .destructive) {
                viewModel.trashLesson(lessonID: lesson.id)
            }
        }
    }

    @ViewBuilder
    private func categoryContextMenu(_ category: SidebarCategory) -> some View {
        Button("Move Up") { viewModel.moveCategory(moduleID: module.id, categoryID: category.id, offset: -1) }
        Button("Move Down") { viewModel.moveCategory(moduleID: module.id, categoryID: category.id, offset: 1) }
        Divider()
        Button("Reset Category Order") { viewModel.resetCategoryOrder(moduleID: module.id) }

        if viewModel.isEditingModule {
            Divider()
            Button("Rename") {
                renameTargetID = category.id
                renameText = category.name
            }
            Button("Transform to Lesson") {
                viewModel.beginTransform(categoryID: category.id)
            }
            Button("Move to Trash", role: .destructive) {
                viewModel.trashCategory(categoryID: category.id)
            }
        }
    }

    private func newItemRow(
        placeholder: String,
        isAdding: Binding<Bool>,
        text: Binding<String>,
        onCommit: @escaping () -> Void
    ) -> some View {
        Group {
            if isAdding.wrappedValue {
                TextField(placeholder, text: text, onCommit: onCommit)
                    .textFieldStyle(.roundedBorder)
            } else {
                Button {
                    isAdding.wrappedValue = true
                } label: {
                    Label(placeholder, systemImage: "plus.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func lessonIcon(isCompleted: Bool) -> some View {
        Image(systemName: isCompleted ? "checkmark.circle.fill" : "play.rectangle")
            .symbolRenderingMode(.monochrome)
            .foregroundColor(isCompleted ? Color(nsColor: .systemGreen) : Color.accentColor)
            .frame(width: 18, alignment: .center)
            .accessibilityHidden(true)
    }

    private func syncEditableModuleFields() {
        editableModuleName = module.name
        editableDescription = module.description ?? ""
    }

    private func commitModuleName() {
        let trimmed = editableModuleName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != module.name else {
            editableModuleName = module.name
            return
        }
        viewModel.renameCurrentModule(to: trimmed)
    }

    private func commitRename(lessonID: String) {
        commitRename(currentID: lessonID) { viewModel.renameLesson(lessonID: lessonID, to: $0) }
    }

    private func commitRename(categoryID: String) {
        commitRename(currentID: categoryID) { viewModel.renameCategory(categoryID: categoryID, to: $0) }
    }

    private func commitRename(currentID: String, apply: (String) -> Void) {
        guard renameTargetID == currentID else {
            return
        }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        renameTargetID = nil
        guard !trimmed.isEmpty else {
            return
        }
        apply(trimmed)
    }

    private func handleReparentDrop(_ ids: [String], categoryID: String?) -> Bool {
        guard let lessonID = ids.first else {
            return false
        }
        viewModel.moveLesson(lessonID: lessonID, toCategoryID: categoryID)
        return true
    }
}

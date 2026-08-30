import ClassroomCore
import SwiftUI

/// The module structure editor — reached by right-clicking a module card
/// in the gallery and choosing "Open as Editor." Shows the raw filesystem
/// tree for the module alongside its structured Category/Lesson outline,
/// and lets the user reorganize, transform loose folders into lessons, and
/// edit lesson content (media/notes/attachments) directly.
struct ModuleEditorView: View {
    @StateObject private var viewModel: ClassroomEditorViewModel
    let onClose: () -> Void

    @State private var editableModuleName: String
    @State private var editableDescription: String
    @State private var selectedLessonID: String?
    @State private var renameTarget: FileNode?
    @State private var renameText: String = ""
    @State private var newItemParent: FileNode?

    init(
        rootURL: URL,
        moduleRelativePath: String,
        moduleName: String,
        moduleDescription: String?,
        onClose: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: ClassroomEditorViewModel(
            rootURL: rootURL,
            moduleRelativePath: moduleRelativePath,
            moduleName: moduleName,
            moduleDescription: moduleDescription
        ))
        self.onClose = onClose
        _editableModuleName = State(initialValue: moduleName)
        _editableDescription = State(initialValue: moduleDescription ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            HSplitView {
                EditorFileTreeView(viewModel: viewModel)
                    .frame(minWidth: 260, idealWidth: 300)

                HSplitView {
                    EditorStructuredOutlineView(
                        viewModel: viewModel,
                        selectedLessonID: $selectedLessonID,
                        renameTarget: $renameTarget,
                        renameText: $renameText
                    )
                    .frame(minWidth: 300, idealWidth: 360)

                    if let lessonNode = selectedLessonNode {
                        EditorLessonDetailView(viewModel: viewModel, lessonNode: lessonNode)
                            .frame(minWidth: 320, idealWidth: 380)
                    } else {
                        ContentUnavailableView(
                            "No Lesson Selected",
                            systemImage: "play.rectangle",
                            description: Text("Select a lesson to edit its media, notes, and attachments.")
                        )
                        .frame(minWidth: 320, idealWidth: 380)
                    }
                }
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .sheet(item: Binding(
            get: { viewModel.pendingTransform },
            set: { if $0 == nil { viewModel.cancelPendingTransform() } }
        )) { pending in
            TransformDisambiguationSheet(pending: pending, viewModel: viewModel)
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.dismissError()
                    }
                }
            ),
            presenting: viewModel.errorMessage
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    private var selectedLessonNode: FileNode? {
        guard let selectedLessonID else {
            return nil
        }
        return viewModel.node(forRelativePath: selectedLessonID)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Module Name", text: $editableModuleName)
                    .textFieldStyle(.plain)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .onSubmit(commitModuleName)

                Spacer()

                Button("Refresh") { viewModel.refresh() }
                Button("Done") {
                    commitModuleName()
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }

            TextField("Description shown on the module's gallery card (optional)", text: $editableDescription, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1...3)
                .onSubmit(commitDescription)
                .onChange(of: editableDescription) { _, _ in
                    commitDescription()
                }
        }
        .padding(16)
    }

    private func commitModuleName() {
        guard editableModuleName != viewModel.moduleName, !editableModuleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            editableModuleName = viewModel.moduleName
            return
        }
        viewModel.renameModule(to: editableModuleName)
        editableModuleName = viewModel.moduleName
    }

    private func commitDescription() {
        guard editableDescription != viewModel.moduleDescription else {
            return
        }
        viewModel.updateModuleDescription(editableDescription)
    }
}

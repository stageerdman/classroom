import ClassroomCore
import SwiftUI

/// The viewer's own running notes — always editable, regardless of Module
/// edit mode. Backed by `note.md` via `ClassroomBrowserViewModel`.
struct NotesEditorView: View {
    @ObservedObject var viewModel: ClassroomBrowserViewModel
    @Binding var editorHeight: CGFloat
    @Binding var isTargeted: Bool
    let onTextChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Notes")
                    .font(.headline)

                Spacer()

                if viewModel.isNoteDirty {
                    Text("Saving...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            MarkdownNotesView(
                text: Binding(
                    get: { viewModel.noteText },
                    set: { viewModel.updateNoteText($0) }
                ),
                contentHeight: $editorHeight,
                onTextChange: onTextChange
            )
            .frame(minHeight: editorHeight, maxHeight: editorHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .modifier(ConditionalURLDropModifier(isEnabled: viewModel.isEditingModule, isTargeted: $isTargeted) { urls in
                guard let url = urls.first else { return false }
                viewModel.insertNotesLinkForSelectedLesson(fileURL: url)
                return true
            })

            if viewModel.isEditingModule {
                Text("Drop a file here to insert a link to it — the file stays where it is.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let noteErrorMessage = viewModel.noteErrorMessage {
                Text(noteErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }
}

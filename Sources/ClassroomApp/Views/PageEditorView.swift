import ClassroomCore
import SwiftUI

/// The lesson's authored content — read-only unless the containing Module
/// is in edit mode. Backed by `page.md` via `ClassroomBrowserViewModel`.
struct PageEditorView: View {
    @ObservedObject var viewModel: ClassroomBrowserViewModel
    @Binding var editorHeight: CGFloat
    let onTextChange: () -> Void
    var onFocusChange: (Bool) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Page")
                    .font(.headline)

                Spacer()

                if viewModel.isEditingModule, viewModel.isPageDirty {
                    Text("Saving...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            MarkdownNotesView(
                text: Binding(
                    get: { viewModel.pageText },
                    set: { viewModel.updatePageText($0) }
                ),
                contentHeight: $editorHeight,
                onTextChange: onTextChange,
                isEditable: viewModel.isEditingModule,
                onFocusChange: onFocusChange
            )
            .frame(minHeight: editorHeight, maxHeight: editorHeight)

            if !viewModel.isEditingModule, viewModel.pageText.isEmpty {
                Text("This lesson has no page content yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if viewModel.isEditingModule {
                Text("Only editable while the Module is in edit mode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let pageErrorMessage = viewModel.pageErrorMessage {
                Text(pageErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }
}

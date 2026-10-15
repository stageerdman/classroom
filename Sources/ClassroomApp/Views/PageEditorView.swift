import ClassroomCore
import SwiftUI

/// The lesson's authored content — read-only unless the containing Module
/// is in edit mode. Backed by `page.md` via `ClassroomBrowserViewModel`.
struct PageEditorView: View {
    @ObservedObject var viewModel: ClassroomBrowserViewModel
    @Binding var editorHeight: CGFloat
    let onTextChange: () -> Void
    var onFocusChange: (Bool) -> Void = { _ in }
    /// Selecting text in Page offers a floating "Comment" button; this fires
    /// with the selected text to start a comment on it in Notes.
    var onCommentOnSelection: ((String) -> Void)?
    /// A quoted passage to scroll to (from a Notes quote chip), applied when
    /// `scrollRequest` changes.
    var scrollToText: String?
    var scrollRequest: Int = 0
    /// Fill the available height with an internally-scrolling, caret-tracking
    /// editor (pinned layout) rather than growing to fit an outer scroll.
    var scrollsInternally: Bool = false

    var body: some View {
        if scrollsInternally {
            editorStack
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            editorStack
        }
    }

    private var editorStack: some View {
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

            let editor = MarkdownNotesView(
                text: Binding(
                    get: { viewModel.pageText },
                    set: { viewModel.updatePageText($0) }
                ),
                contentHeight: $editorHeight,
                onTextChange: onTextChange,
                documentId: "page:\(viewModel.selectedLesson?.relativePath ?? "none")",
                isEditable: viewModel.isEditingModule,
                onCommentOnSelection: onCommentOnSelection,
                scrollToText: scrollToText,
                scrollRequest: scrollRequest,
                scrollsInternally: scrollsInternally,
                onFocusChange: onFocusChange
            )

            if scrollsInternally {
                editor.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                editor.frame(minHeight: editorHeight, maxHeight: editorHeight)
            }

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

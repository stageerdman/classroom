import ClassroomCore
import SwiftUI

/// Shown when "Transform to Lesson" finds more than one playable file or
/// more than one `.md` file in the folder — the user picks which one is
/// the main one; everything else moves into `Attachments/`.
struct TransformDisambiguationSheet: View {
    let pending: ClassroomEditorViewModel.PendingTransform
    @ObservedObject var viewModel: ClassroomEditorViewModel

    @State private var chosenMedia: URL?
    @State private var chosenNotes: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transform \"\(pending.folderURL.lastPathComponent)\" to a Lesson")
                .font(.title3)
                .fontWeight(.semibold)

            if pending.candidates.mediaFiles.count > 1 {
                picker(title: "Main playable file", options: pending.candidates.mediaFiles, selection: $chosenMedia)
            }

            if pending.candidates.notesFiles.count > 1 {
                picker(title: "Main notes file", options: pending.candidates.notesFiles, selection: $chosenNotes)
            }

            Text("Everything else in this folder moves into Attachments.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    viewModel.cancelPendingTransform()
                }
                Button("Transform") {
                    viewModel.resolvePendingTransform(chosenMedia: chosenMedia, chosenNotes: chosenNotes)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    (pending.candidates.mediaFiles.count > 1 && chosenMedia == nil) ||
                    (pending.candidates.notesFiles.count > 1 && chosenNotes == nil)
                )
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func picker(title: String, options: [URL], selection: Binding<URL?>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)

            Picker(title, selection: selection) {
                Text("Choose one").tag(URL?.none)
                ForEach(options, id: \.self) { url in
                    Text(url.lastPathComponent).tag(URL?.some(url))
                }
            }
            .labelsHidden()
        }
    }
}

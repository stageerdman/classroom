import ClassroomCore
import SwiftUI

/// Opens an arbitrary Markdown file in the app's own live-styled editor —
/// not just the one file a lesson recognizes as its designated notes.
/// Reached by clicking a Markdown ghost/attachment while editing, so
/// "operating with the files inside a lesson" isn't limited to the single
/// notes file the scanner picks out.
struct MarkdownFileSheet: View {
    let fileURL: URL
    let onDismiss: () -> Void

    @State private var text = ""
    @State private var contentHeight: CGFloat = 300
    @State private var errorMessage: String?
    @State private var saveTask: Task<Void, Never>?

    private let notesService = NotesService()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(fileURL.lastPathComponent)
                    .font(.headline)
                Spacer()
                Button("Done") {
                    saveTask?.cancel()
                    saveNow()
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            ScrollView {
                MarkdownNotesView(text: $text, contentHeight: $contentHeight, onTextChange: scheduleSave)
                    .frame(minHeight: contentHeight, maxHeight: contentHeight)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(20)
        .frame(width: 640, height: 520)
        .onAppear(perform: load)
    }

    private func load() {
        do {
            text = try notesService.loadNotes(at: fileURL)
        } catch {
            errorMessage = "Could not load this file."
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else {
                return
            }
            saveNow()
        }
    }

    private func saveNow() {
        do {
            try notesService.saveNotes(text, to: fileURL)
            errorMessage = nil
        } catch {
            errorMessage = "Could not save this file."
        }
    }
}

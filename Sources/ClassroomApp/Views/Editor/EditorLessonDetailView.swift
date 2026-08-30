import AppKit
import ClassroomCore
import SwiftUI

/// The three drop zones for one lesson: hero media (replace, demoting the
/// old file to Attachments), notes (drop inserts a Markdown link in place,
/// no file movement), and attachments (drop adds, X removes to a
/// lesson-local Removed folder).
struct EditorLessonDetailView: View {
    @ObservedObject var viewModel: ClassroomEditorViewModel
    let lessonNode: FileNode

    @State private var notesText = ""
    @State private var noteEditorHeight: CGFloat = 160
    @State private var isTargetedHero = false
    @State private var isTargetedNotes = false
    @State private var isTargetedAttachments = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(lessonNode.name)
                    .font(.title3)
                    .fontWeight(.semibold)

                heroZone
                notesZone
                attachmentsZone
            }
            .padding(16)
        }
        .onAppear { notesText = viewModel.loadLessonNotes(for: lessonNode) }
        .onChange(of: lessonNode.id) { _, _ in notesText = viewModel.loadLessonNotes(for: lessonNode) }
    }

    private var heroZone: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Media")
                .font(.headline)

            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
                .frame(height: 140)
                .overlay {
                    if let mediaURL = viewModel.mediaURL(for: lessonNode) {
                        VStack(spacing: 4) {
                            Image(systemName: "play.rectangle.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text(mediaURL.lastPathComponent)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    } else {
                        Text("Drop a video or audio file here")
                            .foregroundStyle(.secondary)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isTargetedHero ? Color.accentColor : Color.clear, lineWidth: 2)
                )
                .dropDestination(for: URL.self) { urls, _ in
                    guard let url = urls.first else {
                        return false
                    }
                    viewModel.replaceHeroMedia(fileURL: url, for: lessonNode)
                    return true
                } isTargeted: { isTargetedHero = $0 }

            Text("The current media, if any, moves to Attachments when replaced.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var notesZone: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notes")
                .font(.headline)

            MarkdownNotesView(
                text: $notesText,
                contentHeight: $noteEditorHeight,
                onTextChange: { viewModel.saveLessonNotes(notesText, for: lessonNode) }
            )
            .frame(minHeight: noteEditorHeight, maxHeight: noteEditorHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isTargetedNotes ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isTargetedNotes ? 2 : 1)
            )
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else {
                    return false
                }
                viewModel.insertNotesLink(for: url, into: lessonNode)
                notesText = viewModel.loadLessonNotes(for: lessonNode)
                return true
            } isTargeted: { isTargetedNotes = $0 }

            Text("Drop a file here to insert a link to it — the file stays where it is.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var attachmentsZone: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Attachments")
                .font(.headline)

            let attachments = viewModel.attachmentURLs(for: lessonNode)
            if attachments.isEmpty {
                Text("No attachments yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(attachments, id: \.self) { url in
                HStack {
                    Image(systemName: "paperclip")
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        viewModel.removeAttachment(url, from: lessonNode)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .help("Remove — moves to this lesson's Removed folder, doesn't delete")
                }
                .draggable(url)
            }

            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                .foregroundStyle(isTargetedAttachments ? Color.accentColor : Color.secondary)
                .frame(height: 44)
                .overlay(
                    Text("Drop files here to attach")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                )
                .dropDestination(for: URL.self) { urls, _ in
                    for url in urls {
                        viewModel.addAttachment(fileURL: url, to: lessonNode)
                    }
                    return !urls.isEmpty
                } isTargeted: { isTargetedAttachments = $0 }
        }
    }
}

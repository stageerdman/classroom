import AppKit
import LocalClassroomCore
import SwiftUI

struct ClassroomBrowserView: View {
    @StateObject private var viewModel = ClassroomBrowserViewModel()
    @StateObject private var playbackService = PlaybackService()
    @State private var selectedSidebarID: String?
    @State private var noteAutosaveTask: Task<Void, Never>?
    @State private var noteEditorHeight: CGFloat = 180

    var body: some View {
        HStack(spacing: 0) {
            ClassroomSidebarView(
                viewModel: viewModel,
                selectedSidebarID: $selectedSidebarID,
                onSelectLesson: selectLesson
            )
                .frame(width: 310)

            Divider()

            detail
        }
        .onChange(of: viewModel.selectedLessonPath) { _, newValue in
            selectedSidebarID = newValue
            loadSelectedLesson()
        }
        .onReceive(Timer.publish(every: 10, on: .main, in: .common).autoconnect()) { _ in
            saveCurrentPlaybackProgress()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openClassroomRequested)) { _ in
            openFolder()
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshClassroomRequested)) { _ in
            viewModel.refresh()
        }
        .onDisappear {
            noteAutosaveTask?.cancel()
            viewModel.saveSelectedNoteIfNeeded()
        }
        .frame(minWidth: 900, minHeight: 560)
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let selectedLesson = viewModel.selectedLesson {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text(selectedLesson.title)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .lineLimit(2)

                        Spacer()

                        Toggle("Complete", isOn: Binding(
                            get: { viewModel.selectedLesson?.state.completed ?? false },
                            set: { viewModel.setSelectedLessonCompleted($0) }
                        ))
                        .toggleStyle(.checkbox)
                    }

                    if let player = playbackService.player {
                        PlayerView(player: player)
                            .frame(height: 360)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .onDisappear {
                                saveCurrentPlaybackProgress()
                                playbackService.pause()
                            }
                    } else {
                        ContentUnavailableView(
                            "Video Unavailable",
                            systemImage: "exclamationmark.triangle",
                            description: Text(playbackService.errorMessage ?? "The selected video could not be loaded.")
                        )
                        .frame(minHeight: 360)
                    }

                    if let selectedLesson = viewModel.selectedLesson {
                        ProgressView(
                            value: selectedLesson.state.playbackPositionSeconds,
                            total: max(selectedLesson.state.playbackPositionSeconds, playbackService.durationSeconds ?? selectedLesson.state.playbackPositionSeconds, 1)
                        ) {
                            Text("Saved position: \(formatTime(selectedLesson.state.playbackPositionSeconds))")
                        }
                    }

                    notesEditor
                } else if let classroom = viewModel.classroom {
                    Text(classroom.name)
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                    Text("\(classroom.modules.count) module\(classroom.modules.count == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                    Text("Select a lesson from the sidebar.")
                        .foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView(
                        "No Classroom Open",
                        systemImage: "folder",
                        description: Text("Choose a local folder to scan its module and lesson structure.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 420)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var notesEditor: some View {
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
                contentHeight: $noteEditorHeight,
                onTextChange: scheduleNoteAutosave
            )
            .frame(minHeight: noteEditorHeight, maxHeight: noteEditorHeight)

            if let noteErrorMessage = viewModel.noteErrorMessage {
                Text(noteErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private func openFolder() {
        viewModel.saveSelectedNoteIfNeeded()

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose a classroom root folder."

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.openFolder(url)
        }
    }

    private func selectLesson(_ lesson: SidebarLesson) {
        saveCurrentPlaybackProgress()
        selectedSidebarID = lesson.id
        viewModel.selectLesson(lesson)
    }

    private func loadSelectedLesson() {
        guard let selectedLesson = viewModel.selectedLesson else {
            playbackService.clear()
            return
        }

        playbackService.load(url: selectedLesson.videoURL)
        playbackService.resume(to: selectedLesson.state.playbackPositionSeconds)
    }

    private func saveCurrentPlaybackProgress() {
        playbackService.refreshSnapshot()
        viewModel.savePlaybackProgress(
            position: playbackService.currentTimeSeconds,
            duration: playbackService.durationSeconds
        )
    }

    private func scheduleNoteAutosave() {
        noteAutosaveTask?.cancel()
        noteAutosaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else {
                return
            }
            viewModel.saveSelectedNoteIfNeeded()
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
    }
}

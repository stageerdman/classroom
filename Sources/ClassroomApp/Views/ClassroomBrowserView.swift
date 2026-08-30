import AppKit
import ClassroomCore
import SwiftUI

struct ClassroomBrowserView: View {
    @StateObject private var viewModel = ClassroomBrowserViewModel()
    @StateObject private var playbackService = PlaybackService()
    @State private var selectedSidebarID: String?
    @State private var noteAutosaveTask: Task<Void, Never>?
    @State private var noteEditorHeight: CGFloat = 180

    var body: some View {
        Group {
            if let module = viewModel.selectedModule {
                moduleDetailLayout(module: module)
            } else if let classroom = viewModel.classroom {
                ClassroomGalleryView(
                    classroomName: classroom.name,
                    modules: viewModel.galleryModules,
                    onOpenModule: viewModel.openModule
                )
            } else {
                emptyState
            }
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
        .onReceive(NotificationCenter.default.publisher(for: .openRecentClassroomRequested)) { notification in
            openRecent(notification)
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

    private func moduleDetailLayout(module: SidebarModule) -> some View {
        HStack(spacing: 0) {
            ClassroomSidebarView(
                viewModel: viewModel,
                module: module,
                selectedSidebarID: $selectedSidebarID,
                onSelectLesson: selectLesson,
                onBack: { viewModel.closeModule() }
            )
            .frame(width: 310)

            Divider()

            detail
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            if let wordmark = BrandImage.wordmark.image {
                wordmark
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 220)
            }

            ContentUnavailableView(
                "No Classroom Open",
                systemImage: "folder",
                description: Text("Choose a local folder to scan its module and lesson structure.")
            )

            Button("Open Classroom...", action: openFolder)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let selectedLesson = viewModel.selectedLesson {
                    lessonHeader(selectedLesson)

                    if selectedLesson.mediaURL != nil {
                        mediaPlayer
                        playbackProgress(for: selectedLesson)
                    }

                    notesEditor

                    if !selectedLesson.attachmentURLs.isEmpty {
                        attachmentsSection(selectedLesson.attachmentURLs)
                    }
                } else {
                    Text("Select a lesson from the sidebar.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func lessonHeader(_ lesson: Lesson) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(lesson.title)
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
    }

    private var mediaPlayer: some View {
        Group {
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
                    "Media Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(playbackService.errorMessage ?? "The selected media could not be loaded.")
                )
                .frame(minHeight: 360)
            }
        }
    }

    private func playbackProgress(for lesson: Lesson) -> some View {
        ProgressView(
            value: lesson.state.playbackPositionSeconds,
            total: max(lesson.state.playbackPositionSeconds, playbackService.durationSeconds ?? lesson.state.playbackPositionSeconds, 1)
        ) {
            Text("Saved position: \(formatTime(lesson.state.playbackPositionSeconds))")
        }
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

    private func attachmentsSection(_ attachmentURLs: [URL]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Attachments")
                .font(.headline)

            ForEach(attachmentURLs, id: \.self) { url in
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label(url.lastPathComponent, systemImage: "paperclip")
                }
                .buttonStyle(.link)
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

    private func openRecent(_ notification: Notification) {
        guard let path = notification.userInfo?["path"] as? String else {
            return
        }

        viewModel.openRecent(RecentClassroom(path: path))
    }

    private func selectLesson(_ lesson: SidebarLesson) {
        saveCurrentPlaybackProgress()
        selectedSidebarID = lesson.id
        viewModel.selectLesson(lesson)
    }

    private func loadSelectedLesson() {
        guard let selectedLesson = viewModel.selectedLesson, let mediaURL = selectedLesson.mediaURL else {
            playbackService.clear()
            return
        }

        playbackService.load(url: mediaURL)
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

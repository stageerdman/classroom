import AppKit
import LocalClassroomCore
import SwiftUI

struct ClassroomBrowserView: View {
    @StateObject private var viewModel = ClassroomBrowserViewModel()
    @StateObject private var playbackService = PlaybackService()
    @State private var selectedSidebarID: String?
    @State private var noteAutosaveTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
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
        .background(WindowConfigurator().frame(width: 0, height: 0))
        .frame(minWidth: 900, minHeight: 560)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedSidebarID) {
                if let sidebar = viewModel.sidebar {
                    Section(sidebar.title) {
                        classroomProgressHeader

                        ForEach(sidebar.modules) { module in
                            DisclosureGroup {
                                ForEach(module.directLessons) { lesson in
                                    lessonRow(lesson)
                                }

                                ForEach(module.categories) { category in
                                    DisclosureGroup(category.name) {
                                        ForEach(category.lessons) { lesson in
                                            lessonRow(lesson)
                                        }
                                    }
                                }
                            } label: {
                                Label(module.name, systemImage: "rectangle.stack")
                            }
                        }
                    }

                    if sidebar.warningCount > 0 {
                        Section("Warnings") {
                            Label("\(sidebar.warningCount) structural warning\(sidebar.warningCount == 1 ? "" : "s")", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                } else {
                    Section("Classroom") {
                        Text("Open a folder to begin.")
                            .foregroundStyle(.secondary)
                    }
                }

                if !viewModel.recentClassrooms.isEmpty {
                    Section("Recent") {
                        ForEach(viewModel.recentClassrooms) { recent in
                            HStack {
                                Button {
                                    viewModel.openRecent(recent)
                                } label: {
                                    Label(recent.name, systemImage: "clock")
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)

                                Spacer()

                                Button {
                                    viewModel.removeRecent(recent)
                                } label: {
                                    Image(systemName: "xmark")
                                }
                                .buttonStyle(.borderless)
                                .help("Remove from recent classrooms")
                            }
                        }
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
                            .frame(minHeight: 360)
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

                    lessonNavigationControls
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

    private var classroomProgressHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Progress")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Text("\(viewModel.classroomProgress.completedLessons)/\(viewModel.classroomProgress.totalLessons) complete")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: viewModel.classroomProgress.percentage) {
                EmptyView()
            } currentValueLabel: {
                Text(viewModel.classroomProgress.percentageText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var lessonNavigationControls: some View {
        HStack(spacing: 10) {
            Button {
                playbackService.seek(to: max(0, (playbackService.player?.currentTime().seconds ?? 0) - 10))
            } label: {
                Label("Back 10 Seconds", systemImage: "gobackward.10")
            }
            .disabled(playbackService.player == nil)

            Button {
                playbackService.seek(to: (playbackService.player?.currentTime().seconds ?? 0) + 10)
            } label: {
                Label("Forward 10 Seconds", systemImage: "goforward.10")
            }
            .disabled(playbackService.player == nil)

            Picker("Speed", selection: Binding(
                get: { playbackService.playbackRate },
                set: { playbackService.setPlaybackRate($0) }
            )) {
                Text("0.5x").tag(Float(0.5))
                Text("1x").tag(Float(1))
                Text("1.25x").tag(Float(1.25))
                Text("1.5x").tag(Float(1.5))
                Text("2x").tag(Float(2))
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
            .disabled(playbackService.player == nil)

            Spacer()

            Button(action: selectPreviousLesson) {
                Label("Previous", systemImage: "backward.end")
            }
            .disabled(viewModel.selectedLesson == nil)
            .keyboardShortcut(.leftArrow, modifiers: [.command])

            Button(action: selectNextLesson) {
                Label("Next", systemImage: "forward.end")
            }
            .disabled(viewModel.selectedLesson == nil)
            .keyboardShortcut(.rightArrow, modifiers: [.command])

            if let errorMessage = playbackService.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
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
                onTextChange: scheduleNoteAutosave
            )
            .frame(minHeight: 180)

            if let noteErrorMessage = viewModel.noteErrorMessage {
                Text(noteErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private func lessonRow(_ lesson: SidebarLesson) -> some View {
        HStack {
            Label(lesson.title, systemImage: "play.rectangle")
                .lineLimit(1)
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            saveCurrentPlaybackProgress()
            selectedSidebarID = lesson.id
            viewModel.selectLesson(lesson)
        }
        .tag(lesson.id)
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

    private func loadSelectedLesson() {
        guard let selectedLesson = viewModel.selectedLesson else {
            playbackService.clear()
            return
        }

        playbackService.load(url: selectedLesson.videoURL)
        playbackService.resume(to: selectedLesson.state.playbackPositionSeconds)
    }

    private func selectPreviousLesson() {
        saveCurrentPlaybackProgress()
        viewModel.selectPreviousLesson()
    }

    private func selectNextLesson() {
        saveCurrentPlaybackProgress()
        viewModel.selectNextLesson()
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

    private func saveNotesNow() {
        noteAutosaveTask?.cancel()
        viewModel.saveSelectedNoteExplicitly()
    }

    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
    }
}

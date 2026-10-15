import AppKit
import ClassroomCore
import SwiftUI

struct ClassroomBrowserView: View {
    @StateObject private var viewModel = ClassroomBrowserViewModel()
    @StateObject private var playbackService = PlaybackService()
    @StateObject private var thumbnailProvider = ScrubThumbnailProvider()
    @State private var fullScreenController = FullScreenPlayerWindowController()
    @State private var popoutController = PopoutPlayerWindowController()
    @State private var isPoppedOut = false
    @State private var selectedSidebarID: String?
    @State private var noteAutosaveTask: Task<Void, Never>?
    @State private var noteEditorHeight: CGFloat = 180
    @State private var pageAutosaveTask: Task<Void, Never>?
    @State private var pageEditorHeight: CGFloat = 180
    @State private var isTargetedHero = false
    @State private var isTargetedNotes = false
    @State private var isTargetedAttachments = false
    @State private var noteFocusRequest = 0
    @State private var openMarkdownFileURL: URL?
    @State private var arrowKeyMonitor: Any?
    /// Page∥Notes split: `true` keeps both panes in one shared scroll (they
    /// move together, the default); `false` gives each pane its own scroll.
    @State private var scrollLinked = true

    var body: some View {
        Group {
            if let module = viewModel.selectedModule {
                moduleDetailLayout(module: module)
            } else if let classroom = viewModel.classroom {
                ClassroomGalleryView(
                    classroomName: classroom.name,
                    modules: viewModel.galleryModules,
                    onOpenModule: viewModel.openModule,
                    onOpenEditor: { moduleID in
                        viewModel.openModule(moduleID)
                        viewModel.setEditingModule(true)
                    }
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
        .onReceive(NotificationCenter.default.publisher(for: .undoEditRequested)) { _ in
            viewModel.undoManager.undo()
        }
        .onReceive(NotificationCenter.default.publisher(for: .redoEditRequested)) { _ in
            viewModel.undoManager.redo()
        }
        .onAppear { installArrowKeyMonitor() }
        .onDisappear {
            removeArrowKeyMonitor()
            noteAutosaveTask?.cancel()
            pageAutosaveTask?.cancel()
            viewModel.saveSelectedNoteIfNeeded()
            viewModel.saveSelectedPageIfNeeded()
        }
        .frame(minWidth: 900, minHeight: 560)
        .sheet(isPresented: Binding(
            get: { openMarkdownFileURL != nil },
            set: { if !$0 { openMarkdownFileURL = nil } }
        )) {
            if let openMarkdownFileURL {
                MarkdownFileSheet(fileURL: openMarkdownFileURL, onDismiss: { self.openMarkdownFileURL = nil })
            }
        }
    }

    private func moduleDetailLayout(module: SidebarModule) -> some View {
        HStack(spacing: 0) {
            ClassroomSidebarView(
                viewModel: viewModel,
                module: module,
                selectedSidebarID: $selectedSidebarID,
                onSelectLesson: selectLesson,
                onBack: { viewModel.closeModule() },
                onOpenGhostFile: openFile
            )
            .frame(width: 310)

            Divider()

            detail
        }
    }

    private var emptyState: some View {
        Group {
            if viewModel.recentClassrooms.isEmpty {
                firstRunState
            } else {
                RecentClassroomsEmptyStateView(
                    recents: viewModel.recentClassrooms,
                    errorMessage: viewModel.errorMessage,
                    onOpen: viewModel.openRecent,
                    onRemove: viewModel.removeRecent,
                    onOpenDifferent: openFolder
                )
            }
        }
    }

    private var firstRunState: some View {
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

    /// Whether the transcript is one of the visible sections. Transcript needs
    /// to follow playback and recenter in its own scroll while the video stays
    /// put, so its presence switches the detail area from the usual single
    /// page-scroll to a pinned-video + scrolling-content layout.
    private var isTranscriptMode: Bool {
        viewModel.selectedContentSections.contains(.transcript)
    }

    /// Page∥Notes is the one split where linked/independent scrolling is a
    /// meaningful choice — a transcript pane always scrolls on its own to
    /// follow playback, so the link toggle only applies here.
    private var isPageNotesSplit: Bool {
        viewModel.selectedContentSections.count == 2 && !isTranscriptMode
    }

    /// Pin the header/video/selector and give the content pane its own scroll
    /// region when: the transcript is shown (it needs to follow playback in
    /// place), or a Page∥Notes split is set to scroll independently.
    private var usesPinnedLayout: Bool {
        isTranscriptMode || (isPageNotesSplit && !scrollLinked)
    }

    private var detail: some View {
        Group {
            if let selectedLesson = viewModel.selectedLesson {
                if usesPinnedLayout {
                    pinnedDetail(selectedLesson)
                } else {
                    scrollingDetail(selectedLesson)
                }
            } else {
                ScrollView {
                    Text("Select a lesson from the sidebar.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(32)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The original layout: everything in one vertical scroll. Used for a
    /// single Page/Notes section, or a linked Page∥Notes split (both panes
    /// share this one scroll, so they move together).
    private func scrollingDetail(_ selectedLesson: Lesson) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                lessonHeader(selectedLesson)

                if selectedLesson.mediaURL != nil || viewModel.isEditingModule {
                    mediaPlayer
                }

                selectorRow

                LessonContentPane(sections: viewModel.selectedContentSections) { section in
                    sectionView(section)
                }

                if !selectedLesson.attachmentURLs.isEmpty || viewModel.isEditingModule {
                    attachmentsSection(selectedLesson.attachmentURLs)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(32)
        }
    }

    /// Pinned layout: header, video and the section selector stay at the top;
    /// the content pane fills the remaining height and each section scrolls on
    /// its own. Used for the transcript (so it can follow playback without
    /// pushing the video away) and for an unlinked Page∥Notes split.
    private func pinnedDetail(_ selectedLesson: Lesson) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            lessonHeader(selectedLesson)

            if selectedLesson.mediaURL != nil || viewModel.isEditingModule {
                mediaPlayer
            }

            selectorRow

            LessonContentPane(sections: viewModel.selectedContentSections) { section in
                if section == .transcript {
                    sectionView(section)
                } else {
                    // Page/Notes editors size to their content and rely on an
                    // outer scroll; give them one inside the bounded region.
                    ScrollView {
                        sectionView(section)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(32)
    }

    /// The section chips, plus a link/unlink scroll toggle for a Page∥Notes
    /// split.
    private var selectorRow: some View {
        HStack(spacing: 10) {
            LessonContentSectionSelector(
                availableSections: viewModel.availableContentSections,
                selectedSections: viewModel.selectedContentSections,
                onToggle: viewModel.toggleContentSection
            )

            if isPageNotesSplit {
                Button {
                    scrollLinked.toggle()
                } label: {
                    Image(systemName: scrollLinked ? "link" : "link.badge.plus")
                        .font(.subheadline)
                        .foregroundStyle(scrollLinked ? Color.accentColor : Color.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            scrollLinked ? AnyShapeStyle(Color.accentColor.opacity(0.15)) : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                }
                .buttonStyle(.plain)
                .help(scrollLinked
                    ? "Linked scrolling — the panes scroll together. Click to scroll each independently."
                    : "Independent scrolling — each pane scrolls on its own. Click to link them.")
            }
        }
    }

    @ViewBuilder
    private func sectionView(_ section: LessonContentSection) -> some View {
        switch section {
        case .page:
            PageEditorView(
                viewModel: viewModel,
                editorHeight: $pageEditorHeight,
                onTextChange: schedulePageAutosave
            )
        case .notes:
            NotesEditorView(
                viewModel: viewModel,
                playbackService: playbackService,
                editorHeight: $noteEditorHeight,
                isTargeted: $isTargetedNotes,
                focusRequest: noteFocusRequest,
                onTextChange: scheduleNoteAutosave
            )
        case .transcript:
            TranscriptView(
                cues: viewModel.transcriptCues,
                playbackService: playbackService,
                errorMessage: viewModel.transcriptErrorMessage
            )
            // Fresh identity per lesson so the follow state resets and the
            // view recenters on the new lesson's active cue when switching
            // lessons with the transcript tab already open.
            .id(viewModel.selectedLesson?.relativePath)
        }
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

    // MARK: - Arrow-key skip

    /// Left/Right arrows skip the video ±15s — but only when a text view
    /// isn't the first responder, so typing in Page/Notes (or a transcript's
    /// text selection, a rename field, etc.) keeps arrows for cursor movement.
    /// A local key monitor (app-wide, covering the full-screen/popout windows
    /// too) is used instead of a SwiftUI `.keyboardShortcut`, which would
    /// grab arrows globally and fire even mid-edit.
    private func installArrowKeyMonitor() {
        guard arrowKeyMonitor == nil else {
            return
        }
        let service = playbackService
        arrowKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Read the Sendable primitives from the event here (NSEvent isn't
            // Sendable, so it can't cross into the MainActor hop below). The
            // monitor runs on the main thread, so these reads are safe.
            let keyCode = event.keyCode
            let isModified = !event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .subtracting([.function, .numericPad])
                .isEmpty
            // A focused text view (Page/Notes editor, rename field editor,
            // etc.) owns the arrows — don't skip the video.
            let textHasFocus = event.window?.firstResponder is NSText

            guard (keyCode == 123 || keyCode == 124), !isModified, !textHasFocus else {
                return event
            }

            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard service.player != nil else {
                    return false
                }
                if keyCode == 123 {
                    service.skipBackward()
                } else {
                    service.skipForward()
                }
                return true
            }
            return consumed ? nil : event
        }
    }

    private func removeArrowKeyMonitor() {
        if let arrowKeyMonitor {
            NSEvent.removeMonitor(arrowKeyMonitor)
        }
        arrowKeyMonitor = nil
    }

    private var mediaPlayer: some View {
        Group {
            if let player = playbackService.player {
                if playbackService.isAudioOnly {
                    VideoTransportControlsView(
                        playbackService: playbackService,
                        thumbnailProvider: thumbnailProvider,
                        isFullScreen: false,
                        onToggleFullScreen: presentFullScreenPlayer,
                        showsFullScreenButton: false,
                        showsPopoutButton: false,
                        looksLikeOverlay: false,
                        onInsertTimenote: insertTimenoteAtCurrentPlaybackPosition
                    )
                } else if isPoppedOut {
                    poppedOutPlaceholder
                } else {
                    ZStack(alignment: .bottom) {
                        PlayerView(player: player)

                        VideoTransportControlsView(
                            playbackService: playbackService,
                            thumbnailProvider: thumbnailProvider,
                            isFullScreen: false,
                            onToggleFullScreen: presentFullScreenPlayer,
                            onTogglePopout: presentPopoutPlayer,
                            onInsertTimenote: insertTimenoteAtCurrentPlaybackPosition
                        )
                        .padding(12)
                    }
                    .frame(height: 360)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            } else if viewModel.selectedLesson?.mediaURL == nil {
                ContentUnavailableView(
                    "No Media Yet",
                    systemImage: "play.rectangle",
                    description: Text(viewModel.isEditingModule ? "Drop a video or audio file here." : "This lesson has no media.")
                )
                .frame(minHeight: 360)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                ContentUnavailableView(
                    "Media Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(playbackService.errorMessage ?? "The selected media could not be loaded.")
                )
                .frame(minHeight: 360)
            }
        }
        .onDisappear {
            saveCurrentPlaybackProgress()
            playbackService.pause()
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isTargetedHero ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .modifier(ConditionalURLDropModifier(isEnabled: viewModel.isEditingModule, isTargeted: $isTargetedHero) { urls in
            guard let url = urls.first else { return false }
            viewModel.replaceSelectedLessonHeroMedia(fileURL: url)
            return true
        })
    }

    private var poppedOutPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "pip")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("Playing in a floating window")
                .foregroundStyle(.secondary)

            Button("Bring Back", action: returnFromPopout)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }


    private func attachmentsSection(_ attachmentURLs: [URL]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Attachments")
                .font(.headline)

            if attachmentURLs.isEmpty {
                Text("No attachments yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(attachmentURLs, id: \.self) { url in
                HStack {
                    Button {
                        openFile(url)
                    } label: {
                        Label(url.lastPathComponent, systemImage: "paperclip")
                    }
                    .buttonStyle(.link)

                    if viewModel.isEditingModule {
                        Spacer()
                        Button {
                            viewModel.removeAttachmentFromSelectedLesson(url)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .help("Remove — moves to this lesson's Removed folder, doesn't delete")
                    }
                }
                .draggable(url)
            }

            if viewModel.isEditingModule {
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
                            viewModel.addAttachmentToSelectedLesson(fileURL: url)
                        }
                        return !urls.isEmpty
                    } isTargeted: { isTargetedAttachments = $0 }
                    .dropDestination(for: String.self) { ids, _ in
                        guard let payload = ids.first, let path = GhostEntryRow.strippedGhostPath(payload) else {
                            return false
                        }
                        viewModel.addAttachmentToSelectedLesson(fileURL: URL(fileURLWithPath: path))
                        return true
                    }
            }
        }
    }

    /// Markdown opens in the app's own live-styled editor; everything else
    /// opens in whatever app the system has associated with it.
    private func openFile(_ url: URL) {
        if url.pathExtension.lowercased() == "md" {
            openMarkdownFileURL = url
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private func openFolder() {
        viewModel.saveSelectedNoteIfNeeded()
        viewModel.saveSelectedPageIfNeeded()

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
        // A detached window (full-screen or popped-out) holds the
        // previous lesson's `AVPlayer` — never let it linger once we're
        // about to load a different one.
        fullScreenController.dismissIfPresented()
        popoutController.dismissIfPresented()

        guard let selectedLesson = viewModel.selectedLesson, let mediaURL = selectedLesson.mediaURL else {
            playbackService.clear()
            thumbnailProvider.clear()
            return
        }

        playbackService.load(url: mediaURL)
        playbackService.resume(to: selectedLesson.state.playbackPositionSeconds)

        guard !playbackService.isAudioOnly else {
            thumbnailProvider.clear()
            return
        }

        if let classroomRootURL = viewModel.classroom?.rootURL {
            thumbnailProvider.load(
                mediaURL: mediaURL,
                classroomRootURL: classroomRootURL,
                lessonRelativePath: selectedLesson.relativePath
            )
        }
    }

    private func saveCurrentPlaybackProgress() {
        playbackService.refreshSnapshot()
        viewModel.savePlaybackProgress(
            position: playbackService.currentTimeSeconds,
            duration: playbackService.durationSeconds
        )
    }

    private func presentFullScreenPlayer() {
        guard let player = playbackService.player else {
            return
        }

        fullScreenController.present(
            player: player,
            playbackService: playbackService,
            thumbnailProvider: thumbnailProvider
        )
    }

    private func presentPopoutPlayer() {
        guard let player = playbackService.player else {
            return
        }

        isPoppedOut = true
        popoutController.present(
            player: player,
            playbackService: playbackService,
            thumbnailProvider: thumbnailProvider,
            onClose: { isPoppedOut = false }
        )
    }

    private func returnFromPopout() {
        popoutController.dismissIfPresented()
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

    private func insertTimenoteAtCurrentPlaybackPosition() {
        viewModel.insertTimenoteForSelectedLesson(atSeconds: playbackService.currentTimeSeconds)
        noteFocusRequest += 1
    }

    private func schedulePageAutosave() {
        pageAutosaveTask?.cancel()
        pageAutosaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else {
                return
            }
            viewModel.saveSelectedPageIfNeeded()
        }
    }
}

import Combine
import Foundation

@MainActor
public final class ClassroomBrowserViewModel: ObservableObject {
    public struct PendingTransform: Identifiable {
        public let id = UUID()
        public let folderURL: URL
        public let candidates: ClassroomEditorService.TransformCandidates
    }

    @Published public private(set) var classroom: Classroom?
    @Published public private(set) var sidebar: ClassroomSidebar?
    @Published public private(set) var recentClassrooms: [RecentClassroom]
    @Published public private(set) var selectedModuleID: String?
    @Published public private(set) var selectedLessonPath: String?
    @Published public private(set) var selectedLesson: Lesson?
    @Published public private(set) var classroomProgress = ProgressSummary(completedLessons: 0, totalLessons: 0)
    @Published public private(set) var moduleProgress: [ModuleProgressSummary] = []
    @Published public private(set) var galleryModules: [GalleryModule] = []
    @Published public private(set) var noteText = ""
    @Published public private(set) var isNoteDirty = false
    @Published public private(set) var noteErrorMessage: String?
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var isEditingModule = false
    @Published public private(set) var pendingTransform: PendingTransform?

    private let scanner: ClassroomScanner
    private let recentStore: RecentClassroomStore
    private let accessStore: FolderAccessStore
    private let metadataStore: MetadataStore
    private let notesService: NotesService
    private let editorService: ClassroomEditorService
    private var currentRootURL: URL?

    public init(
        scanner: ClassroomScanner = ClassroomScanner(),
        recentStore: RecentClassroomStore = RecentClassroomStore(),
        accessStore: FolderAccessStore = SecurityScopedFolderAccessStore(),
        metadataStore: MetadataStore = MetadataStore(),
        notesService: NotesService = NotesService(),
        editorService: ClassroomEditorService = ClassroomEditorService()
    ) {
        self.scanner = scanner
        self.recentStore = recentStore
        self.accessStore = accessStore
        self.metadataStore = metadataStore
        self.notesService = notesService
        self.editorService = editorService
        self.recentClassrooms = recentStore.list()
    }

    public func openFolder(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        accessStore.saveAccess(for: standardizedURL)
        openResolvedURL(standardizedURL, shouldAddToRecent: true)
    }

    public func openRecent(_ recent: RecentClassroom) {
        saveSelectedNoteIfNeeded()
        let resolvedURL = accessStore.resolvedURL(forPath: recent.path)
        openResolvedURL(resolvedURL, shouldAddToRecent: true)
    }

    public func removeRecent(_ recent: RecentClassroom) {
        recentStore.remove(path: recent.path)
        refreshRecentClassrooms()
    }

    public var selectedModule: SidebarModule? {
        guard let selectedModuleID else {
            return nil
        }

        return sidebar?.modules.first { $0.id == selectedModuleID }
    }

    public func openModule(_ id: String) {
        guard selectedModuleID != id else {
            return
        }

        saveSelectedNoteIfNeeded()
        selectedModuleID = id
        clearSelectedLesson()
    }

    public func closeModule() {
        saveSelectedNoteIfNeeded()
        selectedModuleID = nil
        isEditingModule = false
        clearSelectedLesson()
    }

    public func setEditingModule(_ isEditing: Bool) {
        isEditingModule = isEditing
    }

    public func dismissError() {
        errorMessage = nil
    }

    public func refresh() {
        saveSelectedNoteIfNeeded()

        guard let currentRootURL else {
            errorMessage = "Open a classroom folder before refreshing."
            return
        }

        openResolvedURL(currentRootURL, shouldAddToRecent: false)
    }

    public func selectLesson(_ lesson: SidebarLesson) {
        saveSelectedNoteIfNeeded()
        selectLesson(relativePath: lesson.relativePath)
    }

    public func savePlaybackProgress(position: Double, duration: Double?, now: Date = Date()) {
        guard selectedLesson != nil else {
            return
        }

        updateSelectedLessonState { state in
            ProgressService.updatedState(from: state, position: position, duration: duration, now: now)
        }
    }

    public func setSelectedLessonCompleted(_ completed: Bool) {
        guard selectedLesson != nil else {
            return
        }

        updateSelectedLessonState { state in
            ProgressService.manuallyCompleted(state, completed: completed)
        }
    }

    public func selectNextLesson() {
        saveSelectedNoteIfNeeded()
        selectAdjacentLesson(offset: 1)
    }

    public func selectPreviousLesson() {
        saveSelectedNoteIfNeeded()
        selectAdjacentLesson(offset: -1)
    }

    public func moveModules(from source: IndexSet, to destination: Int) {
        updateOrdering { metadata, sidebar in
            metadata.moduleOrder = OrderingService.moved(sidebar.modules.map(\.id), from: source, to: destination)
        }
    }

    public func moveModule(id: String, offset: Int) {
        updateOrdering { metadata, sidebar in
            metadata.moduleOrder = OrderingService.orderAfterMoving(id: id, in: sidebar.modules.map(\.id), offset: offset)
        }
    }

    public func resetModuleOrder() {
        updateOrdering { metadata, _ in
            metadata.moduleOrder = []
        }
    }

    public func moveDirectLessons(moduleID: String, from source: IndexSet, to destination: Int) {
        updateOrdering { metadata, sidebar in
            guard let module = sidebar.modules.first(where: { $0.id == moduleID }) else {
                return
            }
            metadata.lessonOrder[moduleID] = OrderingService.moved(module.directLessons.map(\.fileName), from: source, to: destination)
        }
    }

    public func moveDirectLesson(moduleID: String, lessonID: String, offset: Int) {
        updateOrdering { metadata, sidebar in
            guard let module = sidebar.modules.first(where: { $0.id == moduleID }) else {
                return
            }
            metadata.lessonOrder[moduleID] = OrderingService.orderAfterMoving(id: lessonID.fileName, in: module.directLessons.map(\.fileName), offset: offset)
        }
    }

    public func resetDirectLessonOrder(moduleID: String) {
        updateOrdering { metadata, _ in
            metadata.lessonOrder.removeValue(forKey: moduleID)
        }
    }

    public func moveCategories(moduleID: String, from source: IndexSet, to destination: Int) {
        updateOrdering { metadata, sidebar in
            guard let module = sidebar.modules.first(where: { $0.id == moduleID }) else {
                return
            }
            metadata.categoryOrder[moduleID] = OrderingService.moved(module.categories.map(\.name), from: source, to: destination)
        }
    }

    public func moveCategory(moduleID: String, categoryID: String, offset: Int) {
        updateOrdering { metadata, sidebar in
            guard let module = sidebar.modules.first(where: { $0.id == moduleID }) else {
                return
            }
            let categoryName = String(categoryID.split(separator: "/").last ?? "")
            metadata.categoryOrder[moduleID] = OrderingService.orderAfterMoving(id: categoryName, in: module.categories.map(\.name), offset: offset)
        }
    }

    public func resetCategoryOrder(moduleID: String) {
        updateOrdering { metadata, _ in
            metadata.categoryOrder.removeValue(forKey: moduleID)
        }
    }

    public func moveCategoryLessons(categoryID: String, from source: IndexSet, to destination: Int) {
        updateOrdering { metadata, sidebar in
            guard let category = sidebar.modules.flatMap(\.categories).first(where: { $0.id == categoryID }) else {
                return
            }
            metadata.lessonOrder[categoryID] = OrderingService.moved(category.lessons.map(\.fileName), from: source, to: destination)
        }
    }

    public func moveCategoryLesson(categoryID: String, lessonID: String, offset: Int) {
        updateOrdering { metadata, sidebar in
            guard let category = sidebar.modules.flatMap(\.categories).first(where: { $0.id == categoryID }) else {
                return
            }
            metadata.lessonOrder[categoryID] = OrderingService.orderAfterMoving(id: lessonID.fileName, in: category.lessons.map(\.fileName), offset: offset)
        }
    }

    public func resetCategoryLessonOrder(categoryID: String) {
        updateOrdering { metadata, _ in
            metadata.lessonOrder.removeValue(forKey: categoryID)
        }
    }

    public func updateNoteText(_ text: String) {
        noteText = text
        isNoteDirty = true
        noteErrorMessage = nil
    }

    public func saveSelectedNoteIfNeeded() {
        guard
            isNoteDirty,
            let selectedLesson,
            !noteText.isEmpty || FileManager.default.fileExists(atPath: notesService.noteURL(for: selectedLesson).path)
        else {
            return
        }

        do {
            try notesService.saveNotes(noteText, for: selectedLesson)
            isNoteDirty = false
            noteErrorMessage = nil
        } catch {
            noteErrorMessage = "Notes could not be saved."
        }
    }

    public func saveSelectedNoteExplicitly() {
        guard let selectedLesson else {
            return
        }

        do {
            try notesService.saveNotes(noteText, for: selectedLesson)
            isNoteDirty = false
            noteErrorMessage = nil
        } catch {
            noteErrorMessage = "Notes could not be saved."
        }
    }

    public static func sidebar(from classroom: Classroom) -> ClassroomSidebar {
        ClassroomSidebar(
            title: classroom.name,
            modules: classroom.modules.map { module in
                SidebarModule(
                    id: module.relativePath,
                    name: module.name,
                    description: module.description,
                    directLessons: module.directLessons.map(Self.sidebarLesson),
                    categories: module.categories.map { category in
                        SidebarCategory(
                            id: category.relativePath,
                            name: category.name,
                            lessons: category.lessons.map(Self.sidebarLesson)
                        )
                    }
                )
            },
            warningCount: classroom.warnings.count
        )
    }

    // MARK: Editing — module

    public func renameCurrentModule(to newName: String) {
        guard let module = currentModuleModel(), let moduleURL = url(forRelativePath: module.relativePath) else {
            return
        }

        do {
            _ = try editorService.rename(moduleURL, to: newName)
            let newRelativePath = trimmedName(newName)
            try migratePath(kind: .module, oldPath: module.relativePath, newPath: newRelativePath)
            selectedModuleID = newRelativePath
            refresh()
        } catch {
            errorMessage = Self.editorErrorMessage(for: error)
        }
    }

    public func updateCurrentModuleDescription(_ text: String) {
        guard let module = currentModuleModel(), let moduleURL = url(forRelativePath: module.relativePath) else {
            return
        }

        do {
            try notesService.saveNotes(text, to: moduleURL.appendingPathComponent(ClassroomScanner.moduleDescriptionFileName))
            refresh()
        } catch {
            errorMessage = "Description could not be saved."
        }
    }

    // MARK: Editing — create

    public func createDirectLesson(name: String) {
        guard let module = currentModuleModel(), let moduleURL = url(forRelativePath: module.relativePath) else {
            return
        }

        do {
            _ = try editorService.createLesson(in: moduleURL, name: name)
            refresh()
        } catch {
            errorMessage = Self.editorErrorMessage(for: error)
        }
    }

    public func createCategory(name: String) {
        guard let module = currentModuleModel(), let moduleURL = url(forRelativePath: module.relativePath) else {
            return
        }

        do {
            _ = try editorService.createCategory(in: moduleURL, name: name)
            refresh()
        } catch {
            errorMessage = Self.editorErrorMessage(for: error)
        }
    }

    public func createLesson(name: String, categoryID: String) {
        guard let categoryURL = url(forRelativePath: categoryID) else {
            return
        }

        do {
            _ = try editorService.createLesson(in: categoryURL, name: name)
            refresh()
        } catch {
            errorMessage = Self.editorErrorMessage(for: error)
        }
    }

    // MARK: Editing — rename / move / trash

    public func renameCategory(categoryID: String, to newName: String) {
        guard let categoryURL = url(forRelativePath: categoryID) else {
            return
        }

        do {
            let newURL = try editorService.rename(categoryURL, to: newName)
            try migratePath(kind: .category, oldPath: categoryID, newPath: relativePath(for: newURL))
            refresh()
        } catch {
            errorMessage = Self.editorErrorMessage(for: error)
        }
    }

    public func renameLesson(lessonID: String, to newName: String) {
        guard let lessonURL = url(forRelativePath: lessonID) else {
            return
        }

        do {
            let newURL = try editorService.rename(lessonURL, to: newName)
            try migratePath(kind: .lesson, oldPath: lessonID, newPath: relativePath(for: newURL))
            if selectedLessonPath == lessonID {
                selectedLessonPath = relativePath(for: newURL)
            }
            refresh()
        } catch {
            errorMessage = Self.editorErrorMessage(for: error)
        }
    }

    /// `destinationCategoryID` is `nil` to move the lesson to the current
    /// module's direct lessons.
    public func moveLesson(lessonID: String, toCategoryID destinationCategoryID: String?) {
        guard
            let lessonURL = url(forRelativePath: lessonID),
            let module = currentModuleModel(),
            let moduleURL = url(forRelativePath: module.relativePath)
        else {
            return
        }

        let destinationURL = destinationCategoryID.flatMap { url(forRelativePath: $0) } ?? moduleURL

        do {
            let newURL = try editorService.move(lessonURL, into: destinationURL)
            try migratePath(kind: .lesson, oldPath: lessonID, newPath: relativePath(for: newURL))
            if selectedLessonPath == lessonID {
                selectedLessonPath = relativePath(for: newURL)
            }
            refresh()
        } catch {
            errorMessage = Self.editorErrorMessage(for: error)
        }
    }

    /// Moves a ghost file or folder (identified by its absolute path, since
    /// it has no relative-path identity in the recognized structure) into
    /// another folder — either a recognized category/module (via
    /// `destinationCategoryID`, `nil` meaning the current module's root) or
    /// another ghost folder (via `destinationFolderURL`).
    public func moveGhost(atAbsolutePath path: String, toCategoryID destinationCategoryID: String?) {
        guard
            let module = currentModuleModel(),
            let moduleURL = url(forRelativePath: module.relativePath)
        else {
            return
        }
        let destinationURL = destinationCategoryID.flatMap { url(forRelativePath: $0) } ?? moduleURL
        moveGhost(atAbsolutePath: path, intoFolderURL: destinationURL)
    }

    public func moveGhost(atAbsolutePath path: String, intoFolderURL destinationURL: URL) {
        let sourceURL = URL(fileURLWithPath: path)
        guard sourceURL.standardizedFileURL != destinationURL.standardizedFileURL else {
            return
        }

        do {
            _ = try editorService.move(sourceURL, into: destinationURL)
            refresh()
        } catch {
            errorMessage = Self.editorErrorMessage(for: error)
        }
    }

    public func trashCategory(categoryID: String) {
        guard let categoryURL = url(forRelativePath: categoryID) else {
            return
        }

        do {
            try editorService.trash(categoryURL)
            if selectedLessonPath?.hasPrefix(categoryID + "/") == true {
                clearSelectedLesson()
            }
            refresh()
        } catch {
            errorMessage = "Could not move to Trash."
        }
    }

    public func trashLesson(lessonID: String) {
        guard let lessonURL = url(forRelativePath: lessonID) else {
            return
        }

        do {
            try editorService.trash(lessonURL)
            if selectedLessonPath == lessonID {
                clearSelectedLesson()
            }
            refresh()
        } catch {
            errorMessage = "Could not move to Trash."
        }
    }

    // MARK: Editing — ghosts (everything on disk not part of the recognized structure)

    public func ghostEntries(inRelativePath relativePath: String, excludingNames knownNames: Set<String>) -> [GhostEntry] {
        guard let folderURL = url(forRelativePath: relativePath) else {
            return []
        }
        return editorService.ghostEntries(in: folderURL, excludingNames: knownNames)
    }

    /// Ghosts inside a ghost folder — since a ghost folder has no
    /// relative-path identity in the recognized structure, everything
    /// directly inside it is a ghost too, recursively, until the user
    /// transforms something into a real lesson.
    public func ghostEntries(inFolderURL folderURL: URL) -> [GhostEntry] {
        editorService.ghostEntries(in: folderURL, excludingNames: [])
    }

    public func ghostEntriesForSelectedLesson() -> [GhostEntry] {
        guard let selectedLesson else {
            return []
        }
        return editorService.lessonGhostEntries(
            lessonFolderURL: selectedLesson.folderURL,
            mediaURL: selectedLesson.mediaURL,
            notesURL: selectedLesson.notesURL
        )
    }

    // MARK: Editing — transform to lesson

    public func beginTransform(categoryID: String) {
        guard let categoryURL = url(forRelativePath: categoryID) else {
            return
        }
        beginTransform(folderURL: categoryURL)
    }

    /// Also used for ghost folders, which aren't part of the recognized
    /// structure yet and so have no relative-path identity of their own —
    /// only a raw URL.
    public func beginTransform(folderURL: URL) {
        let candidates = editorService.transformCandidates(for: folderURL)
        guard candidates.canTransform else {
            errorMessage = Self.editorErrorMessage(
                for: candidates.isAlreadyLesson ? ClassroomEditorService.EditorError.alreadyALesson : ClassroomEditorService.EditorError.hasSubfolders
            )
            return
        }

        if candidates.mediaFiles.count > 1 || candidates.notesFiles.count > 1 {
            pendingTransform = PendingTransform(folderURL: folderURL, candidates: candidates)
        } else {
            performTransform(folderURL: folderURL, chosenMedia: nil, chosenNotes: nil)
        }
    }

    public func resolvePendingTransform(chosenMedia: URL?, chosenNotes: URL?) {
        guard let pendingTransform else {
            return
        }
        performTransform(folderURL: pendingTransform.folderURL, chosenMedia: chosenMedia, chosenNotes: chosenNotes)
        self.pendingTransform = nil
    }

    public func cancelPendingTransform() {
        pendingTransform = nil
    }

    private func performTransform(folderURL: URL, chosenMedia: URL?, chosenNotes: URL?) {
        do {
            try editorService.transformToLesson(folderURL, chosenMedia: chosenMedia, chosenNotes: chosenNotes)
            refresh()
        } catch {
            errorMessage = Self.editorErrorMessage(for: error)
        }
    }

    // MARK: Editing — selected lesson's media / notes link / attachments

    public func replaceSelectedLessonHeroMedia(fileURL: URL) {
        guard let selectedLesson else {
            return
        }

        do {
            try editorService.replaceHeroMedia(lessonFolderURL: selectedLesson.folderURL, newMediaURL: fileURL)
            refresh()
        } catch {
            errorMessage = Self.editorErrorMessage(for: error)
        }
    }

    public func addAttachmentToSelectedLesson(fileURL: URL) {
        guard let selectedLesson else {
            return
        }

        do {
            _ = try editorService.addAttachment(lessonFolderURL: selectedLesson.folderURL, fileURL: fileURL)
            refresh()
        } catch {
            errorMessage = Self.editorErrorMessage(for: error)
        }
    }

    public func removeAttachmentFromSelectedLesson(_ attachmentURL: URL) {
        guard let selectedLesson else {
            return
        }

        do {
            try editorService.removeAttachment(lessonFolderURL: selectedLesson.folderURL, attachmentURL: attachmentURL)
            refresh()
        } catch {
            errorMessage = Self.editorErrorMessage(for: error)
        }
    }

    public func insertNotesLinkForSelectedLesson(fileURL: URL) {
        guard selectedLesson != nil else {
            return
        }

        let link = editorService.notesLinkMarkdown(for: fileURL)
        let separator = noteText.isEmpty || noteText.hasSuffix("\n") ? "" : "\n"
        updateNoteText(noteText + separator + link + "\n")
        saveSelectedNoteExplicitly()
    }

    private func openResolvedURL(_ url: URL, shouldAddToRecent: Bool) {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let scannedClassroom = scanner.scan(rootURL: url)

        if scannedClassroom.warnings.contains(where: { $0.kind == .rootMissing }) {
            currentRootURL = nil
            classroom = nil
            sidebar = nil
            selectedModuleID = nil
            clearSelectedLesson()
            updateProgressSummaries()
            errorMessage = "Classroom folder could not be opened: \(url.path)"
            refreshRecentClassrooms()
            return
        }

        let metadataResult = metadataStore.loadMergeAndSave(classroom: scannedClassroom)
        let mergedClassroom = metadataResult.classroom

        currentRootURL = url
        classroom = mergedClassroom
        sidebar = Self.sidebar(from: mergedClassroom)
        updateProgressSummaries()
        errorMessage = nil

        if let selectedModuleID, !mergedClassroom.modules.contains(where: { $0.relativePath == selectedModuleID }) {
            self.selectedModuleID = nil
            clearSelectedLesson()
        }

        if selectedLessonPath != nil && lesson(for: selectedLessonPath, in: mergedClassroom) == nil {
            clearSelectedLesson()
        } else if selectedLessonPath != nil {
            selectedLesson = lesson(for: selectedLessonPath, in: mergedClassroom)
            loadNotesForSelectedLesson()
        }

        if shouldAddToRecent {
            recentStore.add(url)
            refreshRecentClassrooms()
        }
    }

    private static func sidebarLesson(_ lesson: Lesson) -> SidebarLesson {
        SidebarLesson(
            id: lesson.relativePath,
            title: lesson.title,
            relativePath: lesson.relativePath,
            isCompleted: lesson.state.completed
        )
    }

    private func selectLesson(relativePath: String) {
        guard
            let classroom,
            let selected = lesson(for: relativePath, in: classroom)
        else {
            selectedLessonPath = nil
            selectedLesson = nil
            errorMessage = "Lesson could not be found: \(relativePath)"
            return
        }

        guard FileManager.default.fileExists(atPath: selected.folderURL.path) else {
            selectedLessonPath = nil
            selectedLesson = nil
            errorMessage = "Lesson folder is missing: \(selected.folderURL.path)"
            return
        }

        selectedLessonPath = selected.relativePath
        selectedLesson = selected
        loadNotesForSelectedLesson()
        errorMessage = nil
    }

    private func loadNotesForSelectedLesson() {
        guard let selectedLesson else {
            noteText = ""
            isNoteDirty = false
            noteErrorMessage = nil
            return
        }

        do {
            noteText = try notesService.loadNotes(for: selectedLesson)
            isNoteDirty = false
            noteErrorMessage = nil
        } catch {
            noteText = ""
            isNoteDirty = false
            noteErrorMessage = "Notes could not be loaded."
        }
    }

    private func updateSelectedLessonState(transform: (LessonState) -> LessonState) {
        guard
            let currentRootURL,
            let selectedLessonPath,
            var classroom
        else {
            return
        }

        do {
            let updatedState = try metadataStore.updateLessonState(
                rootURL: currentRootURL,
                relativePath: selectedLessonPath,
                transform: transform
            )
            applyLessonState(updatedState, relativePath: selectedLessonPath, classroom: &classroom)
            self.classroom = classroom
            sidebar = Self.sidebar(from: classroom)
            selectedLesson = lesson(for: selectedLessonPath, in: classroom)
            updateProgressSummaries()
            errorMessage = nil
        } catch {
            errorMessage = "Playback progress could not be saved."
        }
    }

    private func applyLessonState(_ state: LessonState, relativePath: String, classroom: inout Classroom) {
        for moduleIndex in classroom.modules.indices {
            for lessonIndex in classroom.modules[moduleIndex].directLessons.indices
                where classroom.modules[moduleIndex].directLessons[lessonIndex].relativePath == relativePath {
                classroom.modules[moduleIndex].directLessons[lessonIndex].state = state
                return
            }

            for categoryIndex in classroom.modules[moduleIndex].categories.indices {
                for lessonIndex in classroom.modules[moduleIndex].categories[categoryIndex].lessons.indices
                    where classroom.modules[moduleIndex].categories[categoryIndex].lessons[lessonIndex].relativePath == relativePath {
                    classroom.modules[moduleIndex].categories[categoryIndex].lessons[lessonIndex].state = state
                    return
                }
            }
        }
    }

    private func refreshRecentClassrooms() {
        recentClassrooms = recentStore.list()
        NotificationCenter.default.post(name: .recentClassroomsDidChange, object: nil)
    }

    private func clearSelectedLesson() {
        selectedLessonPath = nil
        selectedLesson = nil
        noteText = ""
        isNoteDirty = false
        noteErrorMessage = nil
    }

    private func updateProgressSummaries() {
        guard let classroom else {
            classroomProgress = ProgressSummary(completedLessons: 0, totalLessons: 0)
            moduleProgress = []
            galleryModules = []
            return
        }

        classroomProgress = ProgressService.classroomProgress(for: classroom)
        moduleProgress = ProgressService.moduleProgress(for: classroom)
        galleryModules = Self.galleryModules(from: classroom)
    }

    private static func galleryModules(from classroom: Classroom) -> [GalleryModule] {
        let progressByModule = Dictionary(
            uniqueKeysWithValues: ProgressService.moduleProgress(for: classroom).map { ($0.id, $0.progress) }
        )

        return classroom.modules.map { module in
            GalleryModule(
                id: module.relativePath,
                name: module.name,
                description: module.description,
                progress: progressByModule[module.relativePath] ?? ProgressSummary(completedLessons: 0, totalLessons: 0)
            )
        }
    }

    private func selectAdjacentLesson(offset: Int) {
        let lessons = visibleLessons
        guard !lessons.isEmpty else {
            return
        }

        guard
            let selectedLessonPath,
            let selectedIndex = lessons.firstIndex(where: { $0.relativePath == selectedLessonPath })
        else {
            selectLesson(relativePath: lessons[0].relativePath)
            return
        }

        let nextIndex = selectedIndex + offset
        guard lessons.indices.contains(nextIndex) else {
            return
        }

        selectLesson(relativePath: lessons[nextIndex].relativePath)
    }

    private func updateOrdering(_ transform: (inout ClassroomMetadata, ClassroomSidebar) -> Void) {
        guard
            let currentRootURL,
            let sidebar
        else {
            return
        }

        do {
            _ = try metadataStore.updateOrdering(rootURL: currentRootURL) { metadata in
                transform(&metadata, sidebar)
            }
            openResolvedURL(currentRootURL, shouldAddToRecent: false)
            errorMessage = nil
        } catch {
            errorMessage = "Ordering could not be saved."
        }
    }

    private var visibleLessons: [Lesson] {
        guard let classroom else {
            return []
        }

        return classroom.modules.flatMap { module in
            module.directLessons + module.categories.flatMap(\.lessons)
        }
    }

    private func currentModuleModel() -> ClassroomModule? {
        guard let selectedModuleID, let classroom else {
            return nil
        }
        return classroom.modules.first { $0.relativePath == selectedModuleID }
    }

    private func url(forRelativePath relativePath: String) -> URL? {
        guard let currentRootURL else {
            return nil
        }
        return currentRootURL.appendingPathComponent(relativePath, isDirectory: true)
    }

    private func relativePath(for url: URL) -> String {
        guard let currentRootURL else {
            return url.lastPathComponent
        }

        let rootPath = currentRootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path

        guard path.hasPrefix(rootPath + "/") else {
            return url.lastPathComponent
        }

        return String(path.dropFirst(rootPath.count + 1))
    }

    private func migratePath(kind: ClassroomNodeKind, oldPath: String, newPath: String) throws {
        guard let currentRootURL, oldPath != newPath else {
            return
        }
        _ = try metadataStore.migratePath(rootURL: currentRootURL, kind: kind, oldPath: oldPath, newPath: newPath)
    }

    private func trimmedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func editorErrorMessage(for error: Error) -> String {
        switch error as? ClassroomEditorService.EditorError {
        case .emptyName:
            return "Name cannot be empty."
        case .invalidCharacters:
            return "Names cannot contain \"/\" or \":\"."
        case .nameCollision:
            return "An item with that name already exists there."
        case .sourceMissing:
            return "The source file could not be found."
        case .alreadyALesson:
            return "This folder is already a lesson."
        case .hasSubfolders:
            return "This folder already contains a lesson, so it can't be transformed directly."
        case nil:
            return "Something went wrong."
        }
    }

    private func lesson(for relativePath: String?, in classroom: Classroom) -> Lesson? {
        guard let relativePath else {
            return nil
        }

        for module in classroom.modules {
            if let lesson = module.directLessons.first(where: { $0.relativePath == relativePath }) {
                return lesson
            }

            for category in module.categories {
                if let lesson = category.lessons.first(where: { $0.relativePath == relativePath }) {
                    return lesson
                }
            }
        }

        return nil
    }
}

private extension SidebarLesson {
    var fileName: String {
        String(relativePath.split(separator: "/").last ?? "")
    }
}

private extension String {
    var fileName: String {
        String(split(separator: "/").last ?? "")
    }
}

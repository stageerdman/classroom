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
    @Published public private(set) var pageText = ""
    @Published public private(set) var isPageDirty = false
    @Published public private(set) var pageErrorMessage: String?
    @Published public private(set) var noteText = ""
    @Published public private(set) var isNoteDirty = false
    @Published public private(set) var noteErrorMessage: String?
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var isEditingModule = false
    @Published public private(set) var pendingTransform: PendingTransform?
    @Published public private(set) var selectedContentSections: [LessonContentSection] = [.page]

    /// Undo/redo for the structural editing operations (rename, create,
    /// move/reparent, transform-to-lesson, trash) — wired to the system
    /// Edit menu's Undo/Redo commands (and Cmd-Z / Cmd-Shift-Z) via
    /// `.environment(\.undoManager, viewModel.undoManager)` on the root
    /// view. Playback progress, notes text, ordering, and lesson media/
    /// attachment edits are intentionally not covered — lower risk, and
    /// notes/ordering already have their own recovery paths.
    public let undoManager: UndoManager = {
        let manager = UndoManager()
        // Without this, grouping is tied to the run loop's notion of an
        // "event" — fine in a normal app, but it means a registration and
        // an immediate `undo()` right after (as in automated tests, or two
        // edits made in the same runloop turn) can land in the same group
        // or hit an unclosed-group state. Grouping every registration
        // explicitly (see `registerUndoRedo` etc.) makes each edit its own
        // undo step regardless of timing.
        manager.groupsByEvent = false
        return manager
    }()

    private let scanner: ClassroomScanner
    private let recentStore: RecentClassroomStore
    private let accessStore: FolderAccessStore
    private let metadataStore: MetadataStore
    private let pageService: PageService
    private let notesService: NotesService
    private let markdownFileService: MarkdownFileService
    private let editorService: ClassroomEditorService
    private var currentRootURL: URL?

    public init(
        scanner: ClassroomScanner = ClassroomScanner(),
        recentStore: RecentClassroomStore = RecentClassroomStore(),
        accessStore: FolderAccessStore = SecurityScopedFolderAccessStore(),
        metadataStore: MetadataStore = MetadataStore(),
        pageService: PageService = PageService(),
        notesService: NotesService = NotesService(),
        markdownFileService: MarkdownFileService = MarkdownFileService(),
        editorService: ClassroomEditorService = ClassroomEditorService()
    ) {
        self.scanner = scanner
        self.recentStore = recentStore
        self.accessStore = accessStore
        self.metadataStore = metadataStore
        self.pageService = pageService
        self.notesService = notesService
        self.markdownFileService = markdownFileService
        self.editorService = editorService
        self.recentClassrooms = recentStore.list()
    }

    public func openFolder(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        accessStore.saveAccess(for: standardizedURL)
        openResolvedURL(standardizedURL, shouldAddToRecent: true)
    }

    public func openRecent(_ recent: RecentClassroom) {
        saveSelectedLessonContentIfNeeded()
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

        saveSelectedLessonContentIfNeeded()
        selectedModuleID = id
        clearSelectedLesson()
    }

    public func closeModule() {
        saveSelectedLessonContentIfNeeded()
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
        saveSelectedLessonContentIfNeeded()

        guard let currentRootURL else {
            errorMessage = "Open a classroom folder before refreshing."
            return
        }

        openResolvedURL(currentRootURL, shouldAddToRecent: false)
    }

    public func selectLesson(_ lesson: SidebarLesson) {
        saveSelectedLessonContentIfNeeded()
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
        saveSelectedLessonContentIfNeeded()
        selectAdjacentLesson(offset: 1)
    }

    public func selectPreviousLesson() {
        saveSelectedLessonContentIfNeeded()
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

    /// Page is only ever edited while `isEditingModule` is true — the UI
    /// switches `MarkdownNotesView` to non-editable otherwise, so this
    /// simply mirrors the Notes save path without re-checking that here.
    public func updatePageText(_ text: String) {
        pageText = text
        isPageDirty = true
        pageErrorMessage = nil
    }

    public func saveSelectedPageIfNeeded() {
        guard
            isPageDirty,
            let selectedLesson,
            !pageText.isEmpty || FileManager.default.fileExists(atPath: pageService.pageURL(for: selectedLesson).path)
        else {
            return
        }

        do {
            try pageService.savePage(pageText, for: selectedLesson)
            isPageDirty = false
            pageErrorMessage = nil
        } catch {
            pageErrorMessage = "Page could not be saved."
        }
    }

    public func toggleContentSection(_ section: LessonContentSection) {
        selectedContentSections = ContentSectionSelectionService.toggling(section, in: selectedContentSections)
    }

    private func saveSelectedLessonContentIfNeeded() {
        saveSelectedNoteIfNeeded()
        saveSelectedPageIfNeeded()
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
        guard let module = currentModuleModel() else {
            return
        }
        let oldPath = module.relativePath
        let oldLeafName = oldPath.fileName

        guard let newPath = performRenameModule(moduleID: oldPath, to: newName) else {
            return
        }

        registerUndoRedo(
            actionName: "Rename",
            undoAction: { [weak self] in self?.performRenameModule(moduleID: newPath, to: oldLeafName) },
            redoAction: { [weak self] in self?.performRenameModule(moduleID: oldPath, to: newName) }
        )
    }

    @discardableResult
    private func performRenameModule(moduleID: String, to newName: String) -> String? {
        guard let moduleURL = url(forRelativePath: moduleID) else {
            return nil
        }

        do {
            _ = try editorService.rename(moduleURL, to: newName)
            let newRelativePath = trimmedName(newName)
            try migratePath(kind: .module, oldPath: moduleID, newPath: newRelativePath)
            selectedModuleID = newRelativePath
            refresh()
            return newRelativePath
        } catch {
            errorMessage = Self.editorErrorMessage(for: error)
            return nil
        }
    }

    public func updateCurrentModuleDescription(_ text: String) {
        guard let module = currentModuleModel(), let moduleURL = url(forRelativePath: module.relativePath) else {
            return
        }

        do {
            try markdownFileService.save(text, to: moduleURL.appendingPathComponent(ClassroomScanner.moduleDescriptionFileName))
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
            let createdURL = try editorService.createLesson(in: moduleURL, name: name)
            refresh()
            registerUndoRedo(
                actionName: "Create Lesson",
                undoAction: { [weak self] in self?.trashAndRefresh(createdURL) },
                redoAction: { [weak self] in self?.recreateLesson(in: moduleURL, name: name) }
            )
        } catch {
            errorMessage = Self.editorErrorMessage(for: error)
        }
    }

    public func createCategory(name: String) {
        guard let module = currentModuleModel(), let moduleURL = url(forRelativePath: module.relativePath) else {
            return
        }

        do {
            let createdURL = try editorService.createCategory(in: moduleURL, name: name)
            refresh()
            registerUndoRedo(
                actionName: "Create Category",
                undoAction: { [weak self] in self?.trashAndRefresh(createdURL) },
                redoAction: { [weak self] in self?.recreateCategory(in: moduleURL, name: name) }
            )
        } catch {
            errorMessage = Self.editorErrorMessage(for: error)
        }
    }

    public func createLesson(name: String, categoryID: String) {
        guard let categoryURL = url(forRelativePath: categoryID) else {
            return
        }

        do {
            let createdURL = try editorService.createLesson(in: categoryURL, name: name)
            refresh()
            registerUndoRedo(
                actionName: "Create Lesson",
                undoAction: { [weak self] in self?.trashAndRefresh(createdURL) },
                redoAction: { [weak self] in self?.recreateLesson(in: categoryURL, name: name) }
            )
        } catch {
            errorMessage = Self.editorErrorMessage(for: error)
        }
    }

    private func recreateLesson(in parentURL: URL, name: String) {
        do {
            _ = try editorService.createLesson(in: parentURL, name: name)
            refresh()
        } catch {
            errorMessage = Self.editorErrorMessage(for: error)
        }
    }

    private func recreateCategory(in parentURL: URL, name: String) {
        do {
            _ = try editorService.createCategory(in: parentURL, name: name)
            refresh()
        } catch {
            errorMessage = Self.editorErrorMessage(for: error)
        }
    }

    /// Undo for "create" — sends the newly created (and possibly since
    /// populated) folder to the real Trash rather than deleting it outright,
    /// so nothing dropped into it before the undo is silently lost.
    private func trashAndRefresh(_ url: URL) {
        let path = relativePath(for: url)
        do {
            try editorService.trash(url)
            if selectedLessonPath == path || selectedLessonPath?.hasPrefix(path + "/") == true {
                clearSelectedLesson()
            }
            refresh()
        } catch {
            errorMessage = "Could not move to Trash."
        }
    }

    // MARK: Editing — rename / move / trash

    public func renameCategory(categoryID: String, to newName: String) {
        let oldLeafName = categoryID.fileName

        guard let newPath = performRenameCategory(categoryID: categoryID, to: newName) else {
            return
        }

        registerUndoRedo(
            actionName: "Rename",
            undoAction: { [weak self] in self?.performRenameCategory(categoryID: newPath, to: oldLeafName) },
            redoAction: { [weak self] in self?.performRenameCategory(categoryID: categoryID, to: newName) }
        )
    }

    @discardableResult
    private func performRenameCategory(categoryID: String, to newName: String) -> String? {
        guard let categoryURL = url(forRelativePath: categoryID) else {
            return nil
        }

        do {
            let newURL = try editorService.rename(categoryURL, to: newName)
            let newPath = relativePath(for: newURL)
            try migratePath(kind: .category, oldPath: categoryID, newPath: newPath)
            refresh()
            return newPath
        } catch {
            errorMessage = Self.editorErrorMessage(for: error)
            return nil
        }
    }

    public func renameLesson(lessonID: String, to newName: String) {
        let oldLeafName = lessonID.fileName

        guard let newPath = performRenameLesson(lessonID: lessonID, to: newName) else {
            return
        }

        registerUndoRedo(
            actionName: "Rename",
            undoAction: { [weak self] in self?.performRenameLesson(lessonID: newPath, to: oldLeafName) },
            redoAction: { [weak self] in self?.performRenameLesson(lessonID: lessonID, to: newName) }
        )
    }

    @discardableResult
    private func performRenameLesson(lessonID: String, to newName: String) -> String? {
        guard let lessonURL = url(forRelativePath: lessonID) else {
            return nil
        }

        do {
            let newURL = try editorService.rename(lessonURL, to: newName)
            let newPath = relativePath(for: newURL)
            try migratePath(kind: .lesson, oldPath: lessonID, newPath: newPath)
            if selectedLessonPath == lessonID {
                selectedLessonPath = newPath
            }
            refresh()
            return newPath
        } catch {
            errorMessage = Self.editorErrorMessage(for: error)
            return nil
        }
    }

    /// `destinationCategoryID` is `nil` to move the lesson to the current
    /// module's direct lessons.
    public func moveLesson(lessonID: String, toCategoryID destinationCategoryID: String?) {
        guard let module = currentModuleModel() else {
            return
        }
        let sourceParentPath = lessonID.parentPath
        let sourceCategoryID: String? = sourceParentPath == module.relativePath ? nil : sourceParentPath

        guard let newPath = performMoveLesson(lessonID: lessonID, toCategoryID: destinationCategoryID) else {
            return
        }

        registerUndoRedo(
            actionName: "Move",
            undoAction: { [weak self] in self?.performMoveLesson(lessonID: newPath, toCategoryID: sourceCategoryID) },
            redoAction: { [weak self] in self?.performMoveLesson(lessonID: lessonID, toCategoryID: destinationCategoryID) }
        )
    }

    @discardableResult
    private func performMoveLesson(lessonID: String, toCategoryID destinationCategoryID: String?) -> String? {
        guard
            let lessonURL = url(forRelativePath: lessonID),
            let module = currentModuleModel(),
            let moduleURL = url(forRelativePath: module.relativePath)
        else {
            return nil
        }

        let destinationURL = destinationCategoryID.flatMap { url(forRelativePath: $0) } ?? moduleURL

        do {
            let newURL = try editorService.move(lessonURL, into: destinationURL)
            let newPath = relativePath(for: newURL)
            try migratePath(kind: .lesson, oldPath: lessonID, newPath: newPath)
            if selectedLessonPath == lessonID {
                selectedLessonPath = newPath
            }
            refresh()
            return newPath
        } catch {
            errorMessage = Self.editorErrorMessage(for: error)
            return nil
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
        let sourceParentURL = sourceURL.deletingLastPathComponent()

        guard let newURL = performMoveGhost(from: sourceURL, into: destinationURL) else {
            return
        }

        registerUndoRedo(
            actionName: "Move",
            undoAction: { [weak self] in self?.performMoveGhost(from: newURL, into: sourceParentURL) },
            redoAction: { [weak self] in self?.performMoveGhost(from: sourceURL, into: destinationURL) }
        )
    }

    @discardableResult
    private func performMoveGhost(from sourceURL: URL, into destinationURL: URL) -> URL? {
        do {
            let newURL = try editorService.move(sourceURL, into: destinationURL)
            refresh()
            return newURL
        } catch {
            errorMessage = Self.editorErrorMessage(for: error)
            return nil
        }
    }

    public func trashCategory(categoryID: String) {
        guard let categoryURL = url(forRelativePath: categoryID) else {
            return
        }

        do {
            let trashedURL = try editorService.trash(categoryURL)
            if selectedLessonPath?.hasPrefix(categoryID + "/") == true {
                clearSelectedLesson()
            }
            refresh()
            registerRestoreUndo(actionName: "Move to Trash", originalURL: categoryURL, trashedURL: trashedURL)
        } catch {
            errorMessage = "Could not move to Trash."
        }
    }

    public func trashLesson(lessonID: String) {
        guard let lessonURL = url(forRelativePath: lessonID) else {
            return
        }

        do {
            let trashedURL = try editorService.trash(lessonURL)
            if selectedLessonPath == lessonID {
                clearSelectedLesson()
            }
            refresh()
            registerRestoreUndo(actionName: "Move to Trash", originalURL: lessonURL, trashedURL: trashedURL)
        } catch {
            errorMessage = "Could not move to Trash."
        }
    }

    /// Trash/restore undo needs its own mutually-recursive pair rather than
    /// the generic `registerUndoRedo` — `FileManager.trashItem` can rename
    /// the item inside the Trash to dodge a collision, so each new trash
    /// produces a *different* URL to restore from, and that has to thread
    /// through every subsequent undo/redo step rather than being fixed at
    /// registration time.
    private func registerRestoreUndo(actionName: String, originalURL: URL, trashedURL: URL) {
        undoManager.beginUndoGrouping()
        undoManager.setActionName(actionName)
        undoManager.registerUndo(withTarget: self) { target in
            target.performRestore(actionName: actionName, originalURL: originalURL, trashedURL: trashedURL)
        }
        undoManager.endUndoGrouping()
    }

    private func performRestore(actionName: String, originalURL: URL, trashedURL: URL) {
        do {
            try editorService.restore(trashedURL, to: originalURL)
            refresh()
            registerTrashUndo(actionName: actionName, originalURL: originalURL)
        } catch {
            errorMessage = "Could not restore from Trash."
        }
    }

    private func registerTrashUndo(actionName: String, originalURL: URL) {
        undoManager.beginUndoGrouping()
        undoManager.setActionName(actionName)
        undoManager.registerUndo(withTarget: self) { target in
            target.performTrash(actionName: actionName, originalURL: originalURL)
        }
        undoManager.endUndoGrouping()
    }

    private func performTrash(actionName: String, originalURL: URL) {
        do {
            let trashedURL = try editorService.trash(originalURL)
            refresh()
            registerRestoreUndo(actionName: actionName, originalURL: originalURL, trashedURL: trashedURL)
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
            let result = try editorService.transformToLesson(folderURL, chosenMedia: chosenMedia, chosenNotes: chosenNotes)
            refresh()
            registerUndoRedo(
                actionName: "Transform to Lesson",
                undoAction: { [weak self] in self?.performUndoTransform(folderURL: folderURL, result: result) },
                redoAction: { [weak self] in self?.performRedoTransform(folderURL: folderURL, chosenMedia: chosenMedia, chosenNotes: chosenNotes) }
            )
        } catch {
            errorMessage = Self.editorErrorMessage(for: error)
        }
    }

    private func performUndoTransform(folderURL: URL, result: ClassroomEditorService.TransformResult) {
        do {
            try editorService.undoTransformToLesson(folderURL, result: result)
            refresh()
        } catch {
            errorMessage = "Could not undo the transform."
        }
    }

    private func performRedoTransform(folderURL: URL, chosenMedia: URL?, chosenNotes: URL?) {
        do {
            _ = try editorService.transformToLesson(folderURL, chosenMedia: chosenMedia, chosenNotes: chosenNotes)
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

    public func ensureContentSectionVisible(_ section: LessonContentSection) {
        guard !selectedContentSections.contains(section) else {
            return
        }
        selectedContentSections = ContentSectionSelectionService.toggling(section, in: selectedContentSections)
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
            loadLessonContentForSelectedLesson()
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
        loadLessonContentForSelectedLesson()
        errorMessage = nil
    }

    private func loadLessonContentForSelectedLesson() {
        loadNotesForSelectedLesson()
        loadPageForSelectedLesson()
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

    private func loadPageForSelectedLesson() {
        guard let selectedLesson else {
            pageText = ""
            isPageDirty = false
            pageErrorMessage = nil
            return
        }

        do {
            pageText = try pageService.loadPage(for: selectedLesson)
            isPageDirty = false
            pageErrorMessage = nil
        } catch {
            pageText = ""
            isPageDirty = false
            pageErrorMessage = "Page could not be loaded."
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
        pageText = ""
        isPageDirty = false
        pageErrorMessage = nil
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

    /// Pushes one undoable step. `undoAction` is what runs if the user hits
    /// Undo right now; `redoAction` is what runs if they then hit Redo.
    /// Each time either fires, it re-registers itself with the two swapped
    /// — that's what keeps Cmd-Z / Cmd-Shift-Z ping-ponging correctly
    /// through Foundation's `UndoManager`, which treats whatever gets
    /// registered *during* an undo/redo handler as the next step in the
    /// opposite direction.
    private func registerUndoRedo(actionName: String, undoAction: @escaping () -> Void, redoAction: @escaping () -> Void) {
        undoManager.beginUndoGrouping()
        undoManager.setActionName(actionName)
        undoManager.registerUndo(withTarget: self) { target in
            undoAction()
            target.registerUndoRedo(actionName: actionName, undoAction: redoAction, redoAction: undoAction)
        }
        undoManager.endUndoGrouping()
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

    var parentPath: String {
        split(separator: "/").dropLast().joined(separator: "/")
    }
}

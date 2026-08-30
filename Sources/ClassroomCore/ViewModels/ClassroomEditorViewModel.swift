import Combine
import Foundation

/// Orchestrates the module editor: every mutating action calls into
/// `ClassroomEditorService` for the actual filesystem operation, then
/// `MetadataStore.migratePath` when that operation changed a tracked
/// node's relative path (so playback/completion/order state follows it),
/// then rescans. No filesystem logic lives here directly.
@MainActor
public final class ClassroomEditorViewModel: ObservableObject {
    public struct PendingTransform: Identifiable {
        public let id = UUID()
        public let folderURL: URL
        public let candidates: ClassroomEditorService.TransformCandidates
    }

    @Published public private(set) var moduleName: String
    @Published public private(set) var moduleDescription: String
    @Published public private(set) var fileTree: [FileNode] = []
    /// The module's direct lesson folders, in saved custom order (falling
    /// back to natural sort for anything not yet ordered) — matches how
    /// normal browsing orders them, so reordering here stays coherent with
    /// the rest of the app.
    @Published public private(set) var orderedDirectLessons: [FileNode] = []
    /// The module's categories, in saved order, each with its own lessons
    /// already ordered too.
    @Published public private(set) var orderedCategories: [FileNode] = []
    @Published public private(set) var pendingTransform: PendingTransform?
    @Published public private(set) var errorMessage: String?

    private let rootURL: URL
    private var moduleRelativePath: String
    private let editorService: ClassroomEditorService
    private let fileTreeScanner: ModuleFileTreeScanner
    private let metadataStore: MetadataStore
    private let notesService: NotesService

    public init(
        rootURL: URL,
        moduleRelativePath: String,
        moduleName: String,
        moduleDescription: String?,
        editorService: ClassroomEditorService = ClassroomEditorService(),
        fileTreeScanner: ModuleFileTreeScanner = ModuleFileTreeScanner(),
        metadataStore: MetadataStore = MetadataStore(),
        notesService: NotesService = NotesService()
    ) {
        self.rootURL = rootURL
        self.moduleRelativePath = moduleRelativePath
        self.moduleName = moduleName
        self.moduleDescription = moduleDescription ?? ""
        self.editorService = editorService
        self.fileTreeScanner = fileTreeScanner
        self.metadataStore = metadataStore
        self.notesService = notesService

        // Normal browsing always merges/creates .local-classroom/classroom.json
        // before the editor can be reached, but don't rely on that — make
        // sure metadata exists so ordering updates below never fail against
        // a genuinely fresh classroom.
        if (try? metadataStore.load(rootURL: rootURL)) == nil {
            try? metadataStore.save(ClassroomMetadata(), rootURL: rootURL)
        }

        refresh()
    }

    public var moduleURL: URL {
        rootURL.appendingPathComponent(moduleRelativePath, isDirectory: true)
    }

    public func refresh() {
        fileTree = fileTreeScanner.scan(moduleURL: moduleURL, rootURL: rootURL)
        let metadata = (try? metadataStore.load(rootURL: rootURL)) ?? ClassroomMetadata()
        let structure = orderedStructure(metadata: metadata)
        orderedDirectLessons = structure.directLessons
        orderedCategories = structure.categories
        errorMessage = nil
    }

    // MARK: Ordering

    public func moveCategories(from source: IndexSet, to destination: Int) {
        updateOrdering { [orderedCategories] metadata in
            metadata.categoryOrder[self.moduleRelativePath] = OrderingService.moved(orderedCategories.map(\.name), from: source, to: destination)
        }
    }

    public func moveDirectLessons(from source: IndexSet, to destination: Int) {
        updateOrdering { [orderedDirectLessons] metadata in
            metadata.lessonOrder[self.moduleRelativePath] = OrderingService.moved(orderedDirectLessons.map(\.name), from: source, to: destination)
        }
    }

    public func moveCategoryLessons(_ categoryNode: FileNode, from source: IndexSet, to destination: Int) {
        updateOrdering { metadata in
            metadata.lessonOrder[categoryNode.id] = OrderingService.moved(categoryNode.children.map(\.name), from: source, to: destination)
        }
    }

    private func orderedStructure(metadata: ClassroomMetadata) -> (directLessons: [FileNode], categories: [FileNode]) {
        let lessons = fileTree.filter { $0.structuralKind == .lesson }
        let categories = fileTree.filter { $0.structuralKind == .category }

        let orderedLessons = OrderingService.ordered(
            lessons,
            savedOrder: metadata.lessonOrder[moduleRelativePath] ?? [],
            id: { $0.name },
            naturalKey: { $0.name }
        )

        let orderedCategories = OrderingService.ordered(
            categories,
            savedOrder: metadata.categoryOrder[moduleRelativePath] ?? [],
            id: { $0.name },
            naturalKey: { $0.name }
        ).map { category -> FileNode in
            var updated = category
            let categoryLessons = category.children.filter { $0.structuralKind == .lesson }
            updated.children = OrderingService.ordered(
                categoryLessons,
                savedOrder: metadata.lessonOrder[category.id] ?? [],
                id: { $0.name },
                naturalKey: { $0.name }
            )
            return updated
        }

        return (orderedLessons, orderedCategories)
    }

    private func updateOrdering(_ transform: @escaping (inout ClassroomMetadata) -> Void) {
        do {
            _ = try metadataStore.updateOrdering(rootURL: rootURL, transform: transform)
            refresh()
        } catch {
            errorMessage = "Ordering could not be saved."
        }
    }

    // MARK: Module identity

    public func updateModuleDescription(_ text: String) {
        moduleDescription = text
        let url = moduleURL.appendingPathComponent(ClassroomScanner.moduleDescriptionFileName)
        do {
            try notesService.saveNotes(text, to: url)
        } catch {
            errorMessage = "Description could not be saved."
        }
    }

    public func renameModule(to newName: String) {
        do {
            _ = try editorService.rename(moduleURL, to: newName)
            let newRelativePath = trimmedName(newName)
            try migratePath(kind: .module, oldPath: moduleRelativePath, newPath: newRelativePath)
            moduleRelativePath = newRelativePath
            moduleName = newRelativePath
            refresh()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    // MARK: Transform

    public func beginTransform(_ node: FileNode) {
        let candidates = editorService.transformCandidates(for: node.url)
        guard candidates.canTransform else {
            errorMessage = Self.message(for: candidates.isAlreadyLesson ? ClassroomEditorService.EditorError.alreadyALesson : ClassroomEditorService.EditorError.hasSubfolders)
            return
        }

        if candidates.mediaFiles.count > 1 || candidates.notesFiles.count > 1 {
            pendingTransform = PendingTransform(folderURL: node.url, candidates: candidates)
        } else {
            performTransform(folderURL: node.url, chosenMedia: nil, chosenNotes: nil)
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
            errorMessage = Self.message(for: error)
        }
    }

    // MARK: Create

    public func createCategory(name: String, in parentNode: FileNode?) {
        do {
            _ = try editorService.createCategory(in: parentNode?.url ?? moduleURL, name: name)
            refresh()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    public func createLesson(name: String, in parentNode: FileNode?) {
        do {
            _ = try editorService.createLesson(in: parentNode?.url ?? moduleURL, name: name)
            refresh()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    // MARK: Rename / move / trash

    /// `node.structuralKind` drives whether metadata migrates — `nil` means
    /// this is an untracked filesystem entry (a loose file, or anything
    /// nested inside a lesson), so it's a plain rename/move with nothing to
    /// migrate.
    public func rename(_ node: FileNode, to newName: String) {
        do {
            let newURL = try editorService.rename(node.url, to: newName)
            if let kind = node.structuralKind, newURL != node.url {
                try migratePath(kind: kind, oldPath: node.id, newPath: relativePath(for: newURL))
            }
            refresh()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    public func move(_ node: FileNode, into destinationNode: FileNode?) {
        let destinationURL = destinationNode?.url ?? moduleURL
        do {
            let newURL = try editorService.move(node.url, into: destinationURL)
            if let kind = node.structuralKind {
                try migratePath(kind: kind, oldPath: node.id, newPath: relativePath(for: newURL))
            }
            refresh()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    public func trash(_ node: FileNode) {
        do {
            try editorService.trash(node.url)
            refresh()
        } catch {
            errorMessage = "Could not move to Trash."
        }
    }

    // MARK: Lesson content: hero / notes link / attachments

    public func replaceHeroMedia(fileURL: URL, for lessonNode: FileNode) {
        do {
            try editorService.replaceHeroMedia(lessonFolderURL: lessonNode.url, newMediaURL: fileURL)
            refresh()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    public func addAttachment(fileURL: URL, to lessonNode: FileNode) {
        do {
            _ = try editorService.addAttachment(lessonFolderURL: lessonNode.url, fileURL: fileURL)
            refresh()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    public func removeAttachment(_ attachmentURL: URL, from lessonNode: FileNode) {
        do {
            try editorService.removeAttachment(lessonFolderURL: lessonNode.url, attachmentURL: attachmentURL)
            refresh()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    public func notesLinkMarkdown(for fileURL: URL) -> String {
        editorService.notesLinkMarkdown(for: fileURL)
    }

    // MARK: Lesson content lookups (derived from the current file tree)

    public func mediaURL(for lessonNode: FileNode) -> URL? {
        lessonNode.children.first {
            !$0.isDirectory && ClassroomScanner.defaultMediaExtensions.contains($0.url.pathExtension.lowercased())
        }?.url
    }

    public func notesURL(for lessonNode: FileNode) -> URL {
        lessonNode.children.first { !$0.isDirectory && $0.url.pathExtension.lowercased() == "md" }?.url
            ?? lessonNode.url.appendingPathComponent(NotesService.defaultNotesFileName)
    }

    public func attachmentURLs(for lessonNode: FileNode) -> [URL] {
        lessonNode.children
            .first { $0.isDirectory && $0.name.lowercased() == ClassroomScanner.attachmentsFolderName }?
            .children.filter { !$0.isDirectory }.map(\.url) ?? []
    }

    public func loadLessonNotes(for lessonNode: FileNode) -> String {
        (try? notesService.loadNotes(at: notesURL(for: lessonNode))) ?? ""
    }

    public func saveLessonNotes(_ text: String, for lessonNode: FileNode) {
        do {
            try notesService.saveNotes(text, to: notesURL(for: lessonNode))
        } catch {
            errorMessage = "Notes could not be saved."
        }
    }

    public func insertNotesLink(for fileURL: URL, into lessonNode: FileNode) {
        let currentText = loadLessonNotes(for: lessonNode)
        let separator = currentText.isEmpty || currentText.hasSuffix("\n") ? "" : "\n"
        let updatedText = currentText + separator + notesLinkMarkdown(for: fileURL) + "\n"
        saveLessonNotes(updatedText, for: lessonNode)
    }

    /// Looks up a node anywhere in the current tree by its relative path
    /// (`FileNode.id`) — used to resolve a dropped file's URL back to its
    /// tracked node, if it has one.
    public func node(forRelativePath relativePath: String) -> FileNode? {
        func search(_ nodes: [FileNode]) -> FileNode? {
            for node in nodes {
                if node.id == relativePath {
                    return node
                }
                if let match = search(node.children) {
                    return match
                }
            }
            return nil
        }
        return search(fileTree)
    }

    // MARK: Private helpers

    private func migratePath(kind: ClassroomNodeKind, oldPath: String, newPath: String) throws {
        guard oldPath != newPath else {
            return
        }
        _ = try metadataStore.migratePath(rootURL: rootURL, kind: kind, oldPath: oldPath, newPath: newPath)
    }

    private func relativePath(for url: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path

        guard path.hasPrefix(rootPath + "/") else {
            return url.lastPathComponent
        }

        return String(path.dropFirst(rootPath.count + 1))
    }

    private func trimmedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func message(for error: Error) -> String {
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
            return "This folder contains subfolders, so it can't be transformed directly."
        case nil:
            return "Something went wrong."
        }
    }
}

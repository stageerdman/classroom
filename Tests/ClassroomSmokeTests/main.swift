import ClassroomCore
import Foundation

struct NoopFolderAccessStore: FolderAccessStore {
    func saveAccess(for url: URL) {}

    func resolvedURL(forPath path: String) -> URL {
        URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fatalError(message)
    }
}

expect(AppInfo.displayName == "Classroom", "Unexpected app display name")

let fileManager = FileManager.default

func leafName(_ relativePath: String) -> String {
    String(relativePath.split(separator: "/").last ?? "")
}

@MainActor func createFile(at base: URL, _ relativePath: String, text: String = "") throws {
    let url = base.appendingPathComponent(relativePath)
    try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

@MainActor func createDirectory(at base: URL, _ relativePath: String) throws {
    try fileManager.createDirectory(
        at: base.appendingPathComponent(relativePath, isDirectory: true),
        withIntermediateDirectories: true
    )
}

/// Builds a Lesson folder: the hidden `.lesson` marker, plus (by default) a
/// media file named after the folder's own leaf name so its path is easy to
/// predict from the call site.
@MainActor func makeLessonFolder(
    at base: URL,
    _ relativePath: String,
    hasMedia: Bool = true,
    mediaExtension: String = "mp4",
    notesFileName: String? = nil,
    notesText: String = ""
) throws {
    let folderURL = base.appendingPathComponent(relativePath, isDirectory: true)
    try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
    try Data().write(to: folderURL.appendingPathComponent(ClassroomScanner.lessonMarkerFileName))

    if hasMedia {
        try Data().write(to: folderURL.appendingPathComponent("\(leafName(relativePath)).\(mediaExtension)"))
    }

    if let notesFileName {
        try Data(notesText.utf8).write(to: folderURL.appendingPathComponent(notesFileName))
    }
}

func lessonMediaURL(at base: URL, _ relativePath: String, extension mediaExtension: String = "mp4") -> URL {
    base.appendingPathComponent(relativePath, isDirectory: true)
        .appendingPathComponent("\(leafName(relativePath)).\(mediaExtension)")
}

func lessonFolderURL(at base: URL, _ relativePath: String) -> URL {
    base.appendingPathComponent(relativePath, isDirectory: true)
}

// MARK: - Scanner: lesson folders, markers, attachments, module descriptions

let root = fileManager.temporaryDirectory
    .appendingPathComponent("ClassroomScannerSmokeTests")
    .appendingPathComponent(UUID().uuidString)

try createFile(at: root, "01 Foundations/description.md", text: "Foundations of the craft.")
try makeLessonFolder(at: root, "01 Foundations/Lesson 2")
try makeLessonFolder(at: root, "01 Foundations/Lesson 10")
try createFile(at: root, "01 Foundations/ignored.pdf")
try makeLessonFolder(at: root, "01 Foundations/.Hidden Lesson")

// Fear has two candidate media files (ambiguous), custom-named notes, and attachments.
let fearFolder = root.appendingPathComponent("01 Foundations/Mindset/Fear", isDirectory: true)
try fileManager.createDirectory(at: fearFolder, withIntermediateDirectories: true)
try Data().write(to: fearFolder.appendingPathComponent(ClassroomScanner.lessonMarkerFileName))
try Data().write(to: fearFolder.appendingPathComponent("Fear.MOV"))
try Data().write(to: fearFolder.appendingPathComponent("Fear.m4v"))
try Data("Fear notes.".utf8).write(to: fearFolder.appendingPathComponent("Fear-Notes.md"))
try createFile(at: root, "01 Foundations/Mindset/Fear/Attachments/Handout.pdf")
try createFile(at: root, "01 Foundations/Mindset/Fear/Attachments/Worksheet.txt")

try makeLessonFolder(at: root, "01 Foundations/Mindset/Identity")
try createFile(at: root, "01 Foundations/Mindset/Too Deep/whatever.txt")
try makeLessonFolder(at: root, "02 Prospecting/Welcome", mediaExtension: "MP4")

let classroom = ClassroomScanner().scan(rootURL: root)

expect(classroom.name == root.lastPathComponent, "Root folder name should become classroom name")
expect(classroom.modules.map(\.name) == ["01 Foundations", "02 Prospecting"], "Modules should come from root child folders")

let foundations = classroom.modules[0]
expect(foundations.description == "Foundations of the craft.", "Module description should be read from description.md")
expect(classroom.modules[1].description == nil, "Modules without description.md should have no description")
expect(foundations.directLessons.map(\.relativePath) == [
    "01 Foundations/Lesson 2",
    "01 Foundations/Lesson 10"
], "Direct lesson folders should be naturally sorted; stray files, unmarked, and hidden folders ignored")
expect(foundations.directLessons[0].mediaURL?.lastPathComponent == "Lesson 2.mp4", "Direct lesson should resolve its media file")
expect(!classroom.modules.flatMap(\.lessons).contains { $0.title == ".Hidden Lesson" }, "Hidden lesson folders should be ignored even with a marker file")

expect(foundations.categories.map(\.name) == ["Mindset"], "Unmarked third-level folders should become categories")
expect(foundations.categories[0].lessons.map(\.title) == ["Fear", "Identity"], "Category lesson folders should be naturally sorted")

let fearLesson = foundations.categories[0].lessons[0]
expect(
    fearLesson.mediaURL?.lastPathComponent == "Fear.MOV" || fearLesson.mediaURL?.lastPathComponent == "Fear.m4v",
    "Ambiguous lesson media should still resolve to one deterministic candidate"
)
expect(fearLesson.notesURL?.lastPathComponent == "Fear-Notes.md", "Lesson notes file should be resolved regardless of its name")
expect(
    Set(fearLesson.attachmentURLs.map(\.lastPathComponent)) == ["Handout.pdf", "Worksheet.txt"],
    "Attachments folder contents should be exposed as attachment URLs"
)

expect(classroom.warnings.contains { $0.kind == .ambiguousLessonMedia }, "Multiple media files in one lesson folder should warn")
expect(classroom.warnings.contains { $0.kind == .unsupportedDepth }, "Unmarked folders past category depth should warn")
expect(classroom.modules[1].directLessons[0].mediaURL?.lastPathComponent == "Welcome.MP4", "Uppercase media extensions should be supported")

let sidebar = ClassroomBrowserViewModel.sidebar(from: classroom)
expect(sidebar.title == classroom.name, "Sidebar title should match classroom name")
expect(sidebar.modules.count == 2, "Sidebar should include scanned modules")
expect(sidebar.modules[0].directLessons.map(\.title) == ["Lesson 2", "Lesson 10"], "Sidebar should map direct lessons")
expect(sidebar.modules[0].directLessons.allSatisfy { !$0.isCompleted }, "Sidebar should expose incomplete lesson state")
expect(sidebar.modules[0].categories[0].lessons.count == 2, "Sidebar should map category lessons")
expect(sidebar.warningCount == classroom.warnings.count, "Sidebar should expose warning count")

let defaultsSuite = "ClassroomSmokeTests.\(UUID().uuidString)"
guard let userDefaults = UserDefaults(suiteName: defaultsSuite) else {
    fatalError("Could not create smoke test user defaults")
}
defer {
    userDefaults.removePersistentDomain(forName: defaultsSuite)
}

let recentStore = RecentClassroomStore(userDefaults: userDefaults, limit: 2)
let secondRoot = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString, isDirectory: true)
let thirdRoot = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString, isDirectory: true)
try fileManager.createDirectory(at: secondRoot, withIntermediateDirectories: true)
try fileManager.createDirectory(at: thirdRoot, withIntermediateDirectories: true)

recentStore.add(root)
recentStore.add(secondRoot)
recentStore.add(root)
expect(recentStore.list().map(\.path) == [root.standardizedFileURL.path, secondRoot.standardizedFileURL.path], "Recent storage should de-duplicate and move reopened classrooms first")
recentStore.add(thirdRoot)
expect(recentStore.list().map(\.path) == [thirdRoot.standardizedFileURL.path, root.standardizedFileURL.path], "Recent storage should enforce its limit")
recentStore.remove(path: root.path)
expect(recentStore.list().map(\.path) == [thirdRoot.standardizedFileURL.path], "Recent storage should remove paths without deleting folders")

// MARK: - View model: selection, navigation, and gallery/module state

let viewModelDefaultsSuite = "ClassroomViewModelSmokeTests.\(UUID().uuidString)"
guard let viewModelDefaults = UserDefaults(suiteName: viewModelDefaultsSuite) else {
    fatalError("Could not create view model smoke test user defaults")
}
defer {
    viewModelDefaults.removePersistentDomain(forName: viewModelDefaultsSuite)
}

let viewModel = await MainActor.run {
    ClassroomBrowserViewModel(
        recentStore: RecentClassroomStore(userDefaults: viewModelDefaults),
        accessStore: NoopFolderAccessStore()
    )
}

await MainActor.run {
    viewModel.openFolder(root)
    expect(viewModel.sidebar?.modules.count == 2, "View model should expose sidebar sections after opening a classroom")
    expect(viewModel.galleryModules.count == 2, "View model should expose gallery modules after opening a classroom")
    expect(viewModel.galleryModules.first { $0.id == "01 Foundations" }?.description == "Foundations of the craft.", "Gallery module should carry the module description")
    expect(viewModel.recentClassrooms.first?.path == root.standardizedFileURL.path, "View model should add opened classrooms to recent storage")
    expect(viewModel.selectedModule == nil, "Opening a classroom should not auto-select a module (gallery is the default view)")

    viewModel.openModule("01 Foundations")
    expect(viewModel.selectedModule?.id == "01 Foundations", "Opening a module should select it")

    guard let firstLesson = viewModel.selectedModule?.directLessons[0] else {
        fatalError("Expected a direct lesson for selection tests")
    }
    viewModel.selectLesson(firstLesson)
    expect(viewModel.selectedLessonPath == "01 Foundations/Lesson 2", "View model should select lessons")
    viewModel.selectNextLesson()
    expect(viewModel.selectedLessonPath == "01 Foundations/Lesson 10", "Next lesson should respect visible order")
    viewModel.selectNextLesson()
    expect(viewModel.selectedLessonPath == "01 Foundations/Mindset/Fear", "Next lesson should move from direct lessons into category lessons")
    viewModel.selectPreviousLesson()
    expect(viewModel.selectedLessonPath == "01 Foundations/Lesson 10", "Previous lesson should respect visible order")

    viewModel.closeModule()
    expect(viewModel.selectedModule == nil, "Closing a module should return to the gallery")
    expect(viewModel.selectedLessonPath == nil, "Closing a module should clear the selected lesson")

    let missingRoot = root.deletingLastPathComponent().appendingPathComponent("Missing Classroom", isDirectory: true)
    viewModel.openFolder(missingRoot)
    expect(viewModel.classroom == nil, "Missing classroom should clear the current classroom")
    expect(viewModel.errorMessage != nil, "Missing classroom should produce a recoverable error state")
}

// MARK: - Metadata: lesson-folder identity, orphaning, malformed recovery

let metadataRoot = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString, isDirectory: true)
let metadataStore = MetadataStore()
let firstMetadataDate = Date(timeIntervalSince1970: 1_800_000_000)
let secondMetadataDate = firstMetadataDate.addingTimeInterval(60)
let thirdMetadataDate = secondMetadataDate.addingTimeInterval(60)

try makeLessonFolder(at: metadataRoot, "Module/Alpha")
let initialMetadataScan = ClassroomScanner().scan(rootURL: metadataRoot)
let initialMetadataResult = metadataStore.loadMergeAndSave(classroom: initialMetadataScan, now: firstMetadataDate)
expect(
    fileManager.fileExists(atPath: metadataStore.metadataURL(rootURL: metadataRoot).path),
    "Missing metadata should create .local-classroom/classroom.json"
)
expect(initialMetadataResult.metadata.schemaVersion == ClassroomMetadata.currentSchemaVersion, "Metadata should use the current schema version")
expect(initialMetadataResult.metadata.lessonState["Module/Alpha"] == LessonState(), "Unknown scanned lessons should receive default state")

var savedMetadata = initialMetadataResult.metadata
savedMetadata.lessonState["Module/Alpha"] = LessonState(
    playbackPositionSeconds: 42,
    completed: true,
    lastOpenedAt: firstMetadataDate
)
try metadataStore.save(savedMetadata, rootURL: metadataRoot)
let reloadedSavedMetadata = try metadataStore.load(rootURL: metadataRoot)
expect(reloadedSavedMetadata == savedMetadata, "Metadata writes should read back identically")

try makeLessonFolder(at: metadataRoot, "Module/Beta")
let addedLessonResult = metadataStore.loadMergeAndSave(classroom: ClassroomScanner().scan(rootURL: metadataRoot), now: secondMetadataDate)
expect(addedLessonResult.metadata.lessonState["Module/Alpha"]?.playbackPositionSeconds == 42, "Existing lesson state should be preserved")
expect(addedLessonResult.metadata.lessonState["Module/Beta"] == LessonState(), "Newly discovered lessons should be added to metadata")

try fileManager.removeItem(at: lessonFolderURL(at: metadataRoot, "Module/Alpha"))
let missingLessonResult = metadataStore.loadMergeAndSave(classroom: ClassroomScanner().scan(rootURL: metadataRoot), now: secondMetadataDate)
expect(missingLessonResult.metadata.lessonState["Module/Alpha"]?.missingSince == secondMetadataDate, "Missing lessons should be marked orphaned")

try makeLessonFolder(at: metadataRoot, "Module/Alpha")
let restoredLessonResult = metadataStore.loadMergeAndSave(classroom: ClassroomScanner().scan(rootURL: metadataRoot), now: thirdMetadataDate)
expect(restoredLessonResult.metadata.lessonState["Module/Alpha"]?.missingSince == nil, "Restored lesson paths should recover old state")
expect(restoredLessonResult.metadata.lessonState["Module/Alpha"]?.playbackPositionSeconds == 42, "Restored lesson paths should preserve playback state")

var orphanedMetadata = restoredLessonResult.metadata
orphanedMetadata.lessonState["Module/Gone"] = LessonState(
    playbackPositionSeconds: 10,
    completed: false,
    lastOpenedAt: nil,
    missingSince: thirdMetadataDate.addingTimeInterval(-31 * 24 * 60 * 60)
)
try metadataStore.save(orphanedMetadata, rootURL: metadataRoot)
let cleanedMetadataResult = metadataStore.loadMergeAndSave(classroom: ClassroomScanner().scan(rootURL: metadataRoot), now: thirdMetadataDate)
expect(cleanedMetadataResult.metadata.lessonState["Module/Gone"] == nil, "Orphaned lesson state older than 30 days should be removed")

let malformedRoot = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString, isDirectory: true)
try makeLessonFolder(at: malformedRoot, "Module/Lesson")
let malformedMetadataDirectory = malformedRoot.appendingPathComponent(MetadataStore.metadataDirectoryName, isDirectory: true)
try fileManager.createDirectory(at: malformedMetadataDirectory, withIntermediateDirectories: true)
try Data("{ nope".utf8).write(to: malformedMetadataDirectory.appendingPathComponent(MetadataStore.metadataFileName))

let malformedResult = metadataStore.loadMergeAndSave(classroom: ClassroomScanner().scan(rootURL: malformedRoot), now: firstMetadataDate)
let malformedBackups = try fileManager.contentsOfDirectory(atPath: malformedMetadataDirectory.path)
    .filter { $0.hasPrefix("classroom.malformed-") }
expect(malformedResult.warnings.contains { $0.kind == .malformedMetadata }, "Malformed metadata should produce a warning")
expect(malformedBackups.count == 1, "Malformed metadata should be backed up")
let recoveredMalformedMetadata = try metadataStore.load(rootURL: malformedRoot)
expect(recoveredMalformedMetadata.lessonState["Module/Lesson"] != nil, "Classroom should remain usable after malformed metadata recovery")

// MARK: - Playback

await MainActor.run {
    let playbackService = PlaybackService()
    let validMediaURL = lessonMediaURL(at: metadataRoot, "Module/Alpha")
    playbackService.load(url: validMediaURL)
    expect(playbackService.player != nil, "Playback service should initialize a player for an existing local media URL")
    expect(playbackService.currentURL == validMediaURL.standardizedFileURL, "Playback service should retain the current URL")

    playbackService.setPlaybackRate(1.5)
    expect(playbackService.playbackRate == 1.5, "Playback service should store supported playback speed")

    playbackService.load(url: metadataRoot.appendingPathComponent("Module/Missing.mp4"))
    expect(playbackService.player == nil, "Missing media should clear the player")
    expect(playbackService.errorMessage != nil, "Missing media should produce a safe playback error")
}

expect(ProgressService.clampedPosition(-5, duration: 100) == 0, "Progress should clamp negative positions")
expect(ProgressService.clampedPosition(150, duration: 100) == 100, "Progress should clamp positions beyond duration")
expect(ProgressService.clampedPosition(25, duration: nil) == 25, "Progress should allow finite positions without known duration")

let autoCompletedState = ProgressService.updatedState(
    from: LessonState(),
    position: 91,
    duration: 100,
    now: firstMetadataDate
)
expect(autoCompletedState.completed, "Progress should auto-complete after 90 percent watched")

let manuallyIncompleteState = ProgressService.updatedState(
    from: ProgressService.manuallyCompleted(LessonState(), completed: false),
    position: 95,
    duration: 100,
    now: firstMetadataDate
)
expect(!manuallyIncompleteState.completed, "Manual incomplete should override automatic completion")
expect(manuallyIncompleteState.completionOverride == .incomplete, "Manual incomplete override should be stored")

// MARK: - Progress summaries through the view model

let progressDefaultsSuite = "ClassroomProgressSmokeTests.\(UUID().uuidString)"
guard let progressDefaults = UserDefaults(suiteName: progressDefaultsSuite) else {
    fatalError("Could not create progress smoke test user defaults")
}
defer {
    progressDefaults.removePersistentDomain(forName: progressDefaultsSuite)
}

let progressViewModel = await MainActor.run {
    ClassroomBrowserViewModel(
        recentStore: RecentClassroomStore(userDefaults: progressDefaults),
        accessStore: NoopFolderAccessStore()
    )
}

await MainActor.run {
    progressViewModel.openFolder(metadataRoot)
    expect(progressViewModel.classroomProgress.totalLessons == 2, "Classroom progress should count visible lessons")

    progressViewModel.openModule("Module")
    guard let alphaLesson = progressViewModel.selectedModule?.directLessons.first(where: { $0.relativePath == "Module/Alpha" }) else {
        fatalError("Expected Alpha lesson for progress tests")
    }

    progressViewModel.selectLesson(alphaLesson)
    progressViewModel.savePlaybackProgress(position: 55, duration: 100, now: thirdMetadataDate)
    expect(progressViewModel.selectedLesson?.state.playbackPositionSeconds == 55, "Saved position should update selected lesson state")
    progressViewModel.setSelectedLessonCompleted(false)
    expect(progressViewModel.selectedLesson?.state.completed == false, "Manual incomplete should update selected lesson state")
    expect(progressViewModel.classroomProgress.completedLessons == 0, "Completion percentage should reflect manual incomplete state")
    progressViewModel.setSelectedLessonCompleted(true)
    expect(progressViewModel.selectedLesson?.state.completed == true, "Manual complete should update selected lesson state")
    expect(progressViewModel.classroomProgress.completedLessons == 1, "Classroom progress should count completed lessons")
    expect(
        progressViewModel.selectedModule?.directLessons.first(where: { $0.relativePath == "Module/Alpha" })?.isCompleted == true,
        "Sidebar lesson state should update after manual completion"
    )
    expect(progressViewModel.classroomProgress.percentage == 0.5, "Completion percentage should be correct")
    expect(progressViewModel.galleryModules.first?.progress.completedLessons == 1, "Gallery module progress should reflect completion")
}

let persistedProgressMetadata = try metadataStore.load(rootURL: metadataRoot)
expect(persistedProgressMetadata.lessonState["Module/Alpha"]?.playbackPositionSeconds == 55, "Playback state should survive metadata reload")
expect(persistedProgressMetadata.lessonState["Module/Alpha"]?.completed == true, "Completion state should survive metadata reload")

// MARK: - Notes: default filename convention, load/save, autosave-on-switch

let notesService = NotesService()
let alphaFolderURL = lessonFolderURL(at: metadataRoot, "Module/Alpha")
let alphaNoteURL = alphaFolderURL.appendingPathComponent(NotesService.defaultNotesFileName)
let betaFolderURL = lessonFolderURL(at: metadataRoot, "Module/Beta")
let betaNoteURL = betaFolderURL.appendingPathComponent(NotesService.defaultNotesFileName)
let alphaLessonForNotes = Lesson(
    relativePath: "Module/Alpha",
    folderURL: alphaFolderURL,
    mediaURL: lessonMediaURL(at: metadataRoot, "Module/Alpha"),
    notesURL: nil,
    title: "Alpha"
)

expect(notesService.noteURL(for: alphaLessonForNotes) == alphaNoteURL, "Lessons without an existing notes file should fall back to the default notes filename")
let missingAlphaNoteText = try notesService.loadNotes(for: alphaLessonForNotes)
expect(missingAlphaNoteText == "", "Missing notes should load as empty text")
expect(!fileManager.fileExists(atPath: alphaNoteURL.path), "Missing notes should stay absent until saved")

try notesService.saveNotes("# Alpha\n\nPlain UTF-8 notes.", for: alphaLessonForNotes)
expect(fileManager.fileExists(atPath: alphaNoteURL.path), "Saving notes should create the Markdown file")
let savedAlphaNoteText = try notesService.loadNotes(for: alphaLessonForNotes)
expect(savedAlphaNoteText == "# Alpha\n\nPlain UTF-8 notes.", "Existing UTF-8 notes should load")

let notesDefaultsSuite = "ClassroomNotesSmokeTests.\(UUID().uuidString)"
guard let notesDefaults = UserDefaults(suiteName: notesDefaultsSuite) else {
    fatalError("Could not create notes smoke test user defaults")
}
defer {
    notesDefaults.removePersistentDomain(forName: notesDefaultsSuite)
}

let notesViewModel = await MainActor.run {
    ClassroomBrowserViewModel(
        recentStore: RecentClassroomStore(userDefaults: notesDefaults),
        accessStore: NoopFolderAccessStore()
    )
}

await MainActor.run {
    notesViewModel.openFolder(metadataRoot)
    notesViewModel.openModule("Module")

    guard
        let module = notesViewModel.selectedModule,
        let alphaSidebarLesson = module.directLessons.first(where: { $0.relativePath == "Module/Alpha" }),
        let betaSidebarLesson = module.directLessons.first(where: { $0.relativePath == "Module/Beta" })
    else {
        fatalError("Expected Alpha and Beta lessons for notes tests")
    }

    notesViewModel.selectLesson(alphaSidebarLesson)
    expect(notesViewModel.noteText == "# Alpha\n\nPlain UTF-8 notes.", "Selecting a lesson should load existing notes")
    notesViewModel.updateNoteText("Saved before switching")
    notesViewModel.selectLesson(betaSidebarLesson)
    expect(notesViewModel.noteText == "", "Selecting a lesson with no notes should show an empty editor")
}

let switchedAlphaNoteText = try String(contentsOf: alphaNoteURL, encoding: .utf8)
expect(switchedAlphaNoteText == "Saved before switching", "Switching lessons should save dirty notes")
expect(!fileManager.fileExists(atPath: betaNoteURL.path), "Empty untouched notes should not create a file")

let preservedNotesDirectory = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString, isDirectory: true)
try fileManager.createDirectory(at: preservedNotesDirectory, withIntermediateDirectories: true)
let preservedNoteURL = preservedNotesDirectory.appendingPathComponent("Locked.md")
try "Original".write(to: preservedNoteURL, atomically: true, encoding: .utf8)
try fileManager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: preservedNotesDirectory.path)
var didFailToSaveLockedNote = false
do {
    try notesService.saveNotes("Replacement", to: preservedNoteURL)
} catch {
    didFailToSaveLockedNote = true
}
try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: preservedNotesDirectory.path)
expect(didFailToSaveLockedNote, "Saving into an unwritable notes directory should fail")
let preservedNoteText = try String(contentsOf: preservedNoteURL, encoding: .utf8)
expect(preservedNoteText == "Original", "Failed atomic save should preserve the previous note")

// MARK: - Ordering: saved order keyed by lesson folder name

let orderingRoot = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString, isDirectory: true)
try makeLessonFolder(at: orderingRoot, "Module A/Lesson 2")
try makeLessonFolder(at: orderingRoot, "Module A/Lesson 10")
try makeLessonFolder(at: orderingRoot, "Module A/Category B/Cat Lesson 2")
try makeLessonFolder(at: orderingRoot, "Module A/Category A/Cat Lesson 10")
try makeLessonFolder(at: orderingRoot, "Module B/Welcome")

var orderingMetadata = ClassroomMetadata(
    moduleOrder: ["Module B", "Missing Module"],
    categoryOrder: ["Module A": ["Category B", "Missing Category"]],
    lessonOrder: [
        "Module A": ["Lesson 10", "Missing"],
        "Module A/Category A": ["Cat Lesson 10"]
    ]
)
try metadataStore.save(orderingMetadata, rootURL: orderingRoot)

let orderedResult = metadataStore.loadMergeAndSave(classroom: ClassroomScanner().scan(rootURL: orderingRoot), now: firstMetadataDate)
expect(orderedResult.classroom.modules.map(\.name) == ["Module B", "Module A"], "Saved module order should be respected and new modules appended naturally")
expect(orderedResult.classroom.modules[1].categories.map(\.name) == ["Category B", "Category A"], "Saved category order should be respected and new categories appended naturally")
expect(orderedResult.classroom.modules[1].directLessons.map { String($0.relativePath.split(separator: "/").last ?? "") } == ["Lesson 10", "Lesson 2"], "Saved direct lesson ordering should be respected")
expect(orderedResult.metadata.moduleOrder == ["Module B"], "Missing module ordering references should be removed during merge")
expect(orderedResult.metadata.categoryOrder["Module A"] == ["Category B"], "Missing category ordering references should be removed during merge")
expect(orderedResult.metadata.lessonOrder["Module A"] == ["Lesson 10"], "Missing lesson ordering references should be removed during merge")

try makeLessonFolder(at: orderingRoot, "Module C/New")
let appendedOrderingResult = metadataStore.loadMergeAndSave(classroom: ClassroomScanner().scan(rootURL: orderingRoot), now: secondMetadataDate)
expect(appendedOrderingResult.classroom.modules.map(\.name) == ["Module B", "Module A", "Module C"], "New modules should append after saved order in natural order")

let orderingDefaultsSuite = "ClassroomOrderingSmokeTests.\(UUID().uuidString)"
guard let orderingDefaults = UserDefaults(suiteName: orderingDefaultsSuite) else {
    fatalError("Could not create ordering smoke test user defaults")
}
defer {
    orderingDefaults.removePersistentDomain(forName: orderingDefaultsSuite)
}

let orderingViewModel = await MainActor.run {
    ClassroomBrowserViewModel(
        recentStore: RecentClassroomStore(userDefaults: orderingDefaults),
        accessStore: NoopFolderAccessStore()
    )
}

await MainActor.run {
    orderingViewModel.openFolder(orderingRoot)
    orderingViewModel.moveModule(id: "Module C", offset: -1)
    expect(orderingViewModel.galleryModules.map(\.name) == ["Module B", "Module C", "Module A"], "Moving a module should update only module order")
    orderingViewModel.resetModuleOrder()
    expect(orderingViewModel.galleryModules.map(\.name) == ["Module A", "Module B", "Module C"], "Resetting module order should restore filename order")

    orderingViewModel.openModule("Module A")
    orderingViewModel.moveDirectLesson(moduleID: "Module A", lessonID: "Module A/Lesson 10", offset: 1)
    expect(orderingViewModel.selectedModule?.directLessons.map(\.title) == ["Lesson 2", "Lesson 10"], "Moving direct lessons should update only direct lesson order")
}

let persistedOrderingMetadata = try metadataStore.load(rootURL: orderingRoot)
expect(persistedOrderingMetadata.moduleOrder.isEmpty, "Reset module order should survive metadata reload")
expect(persistedOrderingMetadata.lessonOrder["Module A"] == ["Lesson 2", "Lesson 10"], "Direct lesson order should survive metadata reload")

// MARK: - Module editor: transform, create, rename, move, import, attachments

let editorService = ClassroomEditorService()
let editorRoot = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString, isDirectory: true)
try fileManager.createDirectory(at: editorRoot, withIntermediateDirectories: true)

// Transform: sole media/notes auto-picked, extra loose file archived.
let looseFolder = editorRoot.appendingPathComponent("Loose Folder", isDirectory: true)
try fileManager.createDirectory(at: looseFolder, withIntermediateDirectories: true)
try createFile(at: looseFolder, "Video.mp4")
try createFile(at: looseFolder, "Notes.md")
try createFile(at: looseFolder, "Extra.pdf")
try editorService.transformToLesson(looseFolder)
expect(fileManager.fileExists(atPath: looseFolder.appendingPathComponent(ClassroomScanner.lessonMarkerFileName).path), "Transform should add the lesson marker")
expect(fileManager.fileExists(atPath: looseFolder.appendingPathComponent("Video.mp4").path), "Transform should leave the sole media file in place")
expect(fileManager.fileExists(atPath: looseFolder.appendingPathComponent("Attachments/Extra.pdf").path), "Transform should archive unrelated loose files into Attachments")
expect(!fileManager.fileExists(atPath: looseFolder.appendingPathComponent("Extra.pdf").path), "Archived file should no longer be loose")

// Create + rename + move (reparent), with metadata migrating alongside.
let editorScanResult = ClassroomScanner().scan(rootURL: editorRoot)
let editorMetadataStore = MetadataStore()
_ = editorMetadataStore.loadMergeAndSave(classroom: editorScanResult)

let categoryA = try editorService.createCategory(in: editorRoot, name: "Category A")
let categoryB = try editorService.createCategory(in: editorRoot, name: "Category B")
let movedLesson = try editorService.createLesson(in: categoryA, name: "Movable")

var editorMetadata = try editorMetadataStore.load(rootURL: editorRoot)
editorMetadata.lessonState["Category A/Movable"] = LessonState(playbackPositionSeconds: 77, completed: true)
try editorMetadataStore.save(editorMetadata, rootURL: editorRoot)

let renamedLesson = try editorService.rename(movedLesson, to: "Renamed")
_ = try editorMetadataStore.migratePath(rootURL: editorRoot, kind: .lesson, oldPath: "Category A/Movable", newPath: "Category A/Renamed")
let afterRename = try editorMetadataStore.load(rootURL: editorRoot)
expect(afterRename.lessonState["Category A/Renamed"]?.playbackPositionSeconds == 77, "Rename should preserve playback state under the new key")
expect(afterRename.lessonState["Category A/Movable"] == nil, "Old key should be gone after rename migration")

let reparented = try editorService.move(renamedLesson, into: categoryB)
_ = try editorMetadataStore.migratePath(rootURL: editorRoot, kind: .lesson, oldPath: "Category A/Renamed", newPath: "Category B/Renamed")
let afterMove = try editorMetadataStore.load(rootURL: editorRoot)
expect(afterMove.lessonState["Category B/Renamed"]?.completed == true, "Move should preserve completion state under the new key")
expect(fileManager.fileExists(atPath: reparented.path), "Moved lesson folder should exist at its new location")
expect(!fileManager.fileExists(atPath: renamedLesson.path), "Moved lesson folder should no longer exist at its old location")

// Import (move + disambiguate) and attachment lifecycle.
let externalSourceDir = editorRoot.deletingLastPathComponent().appendingPathComponent(UUID().uuidString, isDirectory: true)
try fileManager.createDirectory(at: externalSourceDir, withIntermediateDirectories: true)
let externalFile = externalSourceDir.appendingPathComponent("Handout.pdf")
try Data().write(to: externalFile)
let addedAttachment = try editorService.addAttachment(lessonFolderURL: reparented, fileURL: externalFile)
expect(!fileManager.fileExists(atPath: externalFile.path), "Importing an attachment should move the source, not copy it")
expect(fileManager.fileExists(atPath: addedAttachment.path), "Attachment should land inside the lesson's Attachments folder")

try editorService.removeAttachment(lessonFolderURL: reparented, attachmentURL: addedAttachment)
expect(!fileManager.fileExists(atPath: addedAttachment.path), "Removed attachment should leave the Attachments folder")
expect(fileManager.fileExists(atPath: reparented.appendingPathComponent("Removed/Handout.pdf").path), "Removed attachment should land in the lesson's Removed folder rather than being deleted")

// Raw file tree surfaces Attachments/Removed but never the marker file itself.
let editorTree = ModuleFileTreeScanner().scan(moduleURL: editorRoot, rootURL: editorRoot)
let categoryBNode = editorTree.first { $0.name == "Category B" }
let renamedNode = categoryBNode?.children.first { $0.name == "Renamed" }
expect(renamedNode?.isLessonFolder == true, "Editor tree should flag the moved folder as a lesson")
expect(renamedNode?.children.contains { $0.name == "Removed" } == true, "Editor tree should surface the Removed folder")
expect(renamedNode?.children.contains { $0.name == ClassroomScanner.lessonMarkerFileName } != true, "Editor tree should never surface the raw marker file")

// MARK: - ClassroomEditorViewModel: end-to-end through the orchestration layer

let vmRoot = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString, isDirectory: true)
try createFile(at: vmRoot, "Module A/description.md", text: "Original description.")
try fileManager.createDirectory(at: vmRoot.appendingPathComponent("Module A/Loose Folder", isDirectory: true), withIntermediateDirectories: true)
try createFile(at: vmRoot, "Module A/Loose Folder/Video.mp4")

let editorViewModel = await MainActor.run {
    ClassroomEditorViewModel(
        rootURL: vmRoot,
        moduleRelativePath: "Module A",
        moduleName: "Module A",
        moduleDescription: "Original description."
    )
}

await MainActor.run {
    expect(editorViewModel.fileTree.contains { $0.name == "Loose Folder" }, "Editor view model should surface loose folders")

    let looseNode = editorViewModel.fileTree.first { $0.name == "Loose Folder" }!
    expect(looseNode.structuralKind == .category, "A loose folder directly under a module reads as a Category until it's transformed into a lesson")

    editorViewModel.beginTransform(looseNode)
    expect(editorViewModel.pendingTransform == nil, "A single unambiguous media candidate should not require a picker")
    expect(editorViewModel.fileTree.first { $0.name == "Loose Folder" }?.isLessonFolder == true, "Transform should mark the folder as a lesson")

    editorViewModel.createCategory(name: "New Category", in: nil)
    expect(editorViewModel.fileTree.contains { $0.name == "New Category" && $0.structuralKind == .category }, "New category should appear as a tracked category node")
}

let vmMetadataStore = MetadataStore()
_ = vmMetadataStore.loadMergeAndSave(classroom: ClassroomScanner().scan(rootURL: vmRoot))
var vmMetadata = try vmMetadataStore.load(rootURL: vmRoot)
vmMetadata.lessonState["Module A/Loose Folder"] = LessonState(playbackPositionSeconds: 33, completed: true)
try vmMetadataStore.save(vmMetadata, rootURL: vmRoot)

await MainActor.run {
    editorViewModel.refresh()
    let lessonNode = editorViewModel.fileTree.first { $0.name == "Loose Folder" }!
    let categoryNode = editorViewModel.fileTree.first { $0.name == "New Category" }!

    editorViewModel.move(lessonNode, into: categoryNode)
    editorViewModel.refresh()
}

let afterVMMove = try vmMetadataStore.load(rootURL: vmRoot)
expect(afterVMMove.lessonState["Module A/New Category/Loose Folder"]?.playbackPositionSeconds == 33, "Moving a lesson through the view model should preserve its state under the new key")
expect(afterVMMove.lessonState["Module A/Loose Folder"] == nil, "Old key should be gone after a view-model-driven move")

await MainActor.run {
    editorViewModel.refresh()
    let categoryNode = editorViewModel.fileTree.first { $0.name == "New Category" }!
    let lessonNode = categoryNode.children.first { $0.name == "Loose Folder" }!
    editorViewModel.rename(lessonNode, to: "Renamed Lesson")
    editorViewModel.refresh()
}

let afterVMRename = try vmMetadataStore.load(rootURL: vmRoot)
expect(afterVMRename.lessonState["Module A/New Category/Renamed Lesson"]?.completed == true, "Renaming a lesson through the view model should preserve completion state")

await MainActor.run {
    editorViewModel.updateModuleDescription("Updated description.")
    expect(editorViewModel.moduleDescription == "Updated description.", "View model should track the edited description")
}
let savedDescription = try String(
    contentsOf: vmRoot.appendingPathComponent("Module A/description.md"),
    encoding: .utf8
)
expect(savedDescription == "Updated description.", "Description edits should save to description.md")

await MainActor.run {
    editorViewModel.refresh()
    let categoryNode = editorViewModel.fileTree.first { $0.name == "New Category" }!
    let lessonNode = categoryNode.children.first { $0.name == "Renamed Lesson" }!

    editorViewModel.renameModule(to: "Module A Renamed")
    expect(editorViewModel.moduleName == "Module A Renamed", "Renaming the module should update the view model's own identity")
    expect(fileManager.fileExists(atPath: editorViewModel.moduleURL.path), "The renamed module folder should exist at the view model's updated moduleURL")

    _ = lessonNode
}

let afterModuleRename = try vmMetadataStore.load(rootURL: vmRoot)
expect(afterModuleRename.lessonState["Module A Renamed/New Category/Renamed Lesson"]?.completed == true, "Module rename should cascade metadata to lessons nested under it")

// MARK: - ClassroomEditorViewModel: ordering matches saved custom order

let orderingVMRoot = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString, isDirectory: true)
try makeLessonFolder(at: orderingVMRoot, "Module/Lesson B")
try makeLessonFolder(at: orderingVMRoot, "Module/Lesson A")
try makeLessonFolder(at: orderingVMRoot, "Module/CategoryZ/Cat Lesson 2")
try makeLessonFolder(at: orderingVMRoot, "Module/CategoryZ/Cat Lesson 1")
try makeLessonFolder(at: orderingVMRoot, "Module/CategoryY/Other")

let orderingEditorViewModel = await MainActor.run {
    ClassroomEditorViewModel(rootURL: orderingVMRoot, moduleRelativePath: "Module", moduleName: "Module", moduleDescription: nil)
}

await MainActor.run {
    expect(orderingEditorViewModel.orderedDirectLessons.map(\.name) == ["Lesson A", "Lesson B"], "Direct lessons should start in natural order")
    expect(orderingEditorViewModel.orderedCategories.map(\.name) == ["CategoryY", "CategoryZ"], "Categories should start in natural order")

    orderingEditorViewModel.moveDirectLessons(from: IndexSet(integer: 1), to: 0)
    expect(orderingEditorViewModel.orderedDirectLessons.map(\.name) == ["Lesson B", "Lesson A"], "Moving a direct lesson should update saved order")

    orderingEditorViewModel.moveCategories(from: IndexSet(integer: 1), to: 0)
    expect(orderingEditorViewModel.orderedCategories.map(\.name) == ["CategoryZ", "CategoryY"], "Moving a category should update saved order")

    let categoryZ = orderingEditorViewModel.orderedCategories.first { $0.name == "CategoryZ" }!
    expect(categoryZ.children.map(\.name) == ["Cat Lesson 1", "Cat Lesson 2"], "Category lessons should start in natural order")
    orderingEditorViewModel.moveCategoryLessons(categoryZ, from: IndexSet(integer: 1), to: 0)
}

let persistedOrderingVMMetadata = try MetadataStore().load(rootURL: orderingVMRoot)
expect(persistedOrderingVMMetadata.lessonOrder["Module"] == ["Lesson B", "Lesson A"], "Direct lesson order should persist")
expect(persistedOrderingVMMetadata.categoryOrder["Module"] == ["CategoryZ", "CategoryY"], "Category order should persist")
expect(persistedOrderingVMMetadata.lessonOrder["Module/CategoryZ"] == ["Cat Lesson 2", "Cat Lesson 1"], "Category-scoped lesson order should persist")

await MainActor.run {
    let refreshedCategoryZ = orderingEditorViewModel.orderedCategories.first { $0.name == "CategoryZ" }!
    expect(refreshedCategoryZ.children.map(\.name) == ["Cat Lesson 2", "Cat Lesson 1"], "Reordered category lessons should reflect saved order after refresh")
}

print("ClassroomSmokeTests passed")

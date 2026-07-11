import LocalClassroomCore
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

expect(AppInfo.displayName == "Local Classroom", "Unexpected app display name")

let fileManager = FileManager.default
let root = fileManager.temporaryDirectory
    .appendingPathComponent("LocalClassroomScannerSmokeTests")
    .appendingPathComponent(UUID().uuidString)

@MainActor func createDirectory(_ relativePath: String) throws {
    try fileManager.createDirectory(
        at: root.appendingPathComponent(relativePath, isDirectory: true),
        withIntermediateDirectories: true
    )
}

@MainActor func createFile(_ relativePath: String) throws {
    let url = root.appendingPathComponent(relativePath)
    try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data().write(to: url)
}

try createDirectory("01 Foundations/Mindset")
try createDirectory("02 Prospecting")
try createFile("01 Foundations/Lesson 10.mp4")
try createFile("01 Foundations/Lesson 2.mp4")
try createFile("01 Foundations/ignored.pdf")
try createFile("01 Foundations/.hidden.mp4")
try createFile("01 Foundations/Mindset/Fear.MOV")
try createFile("01 Foundations/Mindset/Fear.m4v")
try createFile("01 Foundations/Mindset/Notes.md")
try createDirectory("01 Foundations/Mindset/Too Deep")
try createFile("02 Prospecting/Welcome.MP4")

let classroom = ClassroomScanner().scan(rootURL: root)

expect(classroom.name == root.lastPathComponent, "Root folder name should become classroom name")
expect(classroom.modules.map(\.name) == ["01 Foundations", "02 Prospecting"], "Modules should come from root child folders")

let foundations = classroom.modules[0]
expect(foundations.directLessons.map(\.relativePath) == [
    "01 Foundations/Lesson 2.mp4",
    "01 Foundations/Lesson 10.mp4"
], "Direct lessons should be naturally sorted and unsupported or hidden files ignored")
expect(foundations.categories.map(\.name) == ["Mindset"], "Third-level folders should become categories")
expect(Set(foundations.categories[0].lessons.map(\.relativePath)) == [
    "01 Foundations/Mindset/Fear.m4v",
    "01 Foundations/Mindset/Fear.MOV"
], "Category videos should be parsed case-insensitively")
expect(classroom.modules[1].directLessons[0].relativePath == "02 Prospecting/Welcome.MP4", "Uppercase video extensions should be supported")
expect(classroom.warnings.contains { $0.kind == .unsupportedDepth }, "Over-deep folders should generate warnings")
expect(classroom.warnings.contains { $0.kind == .duplicateVideoBasename }, "Duplicate video basenames should generate warnings")

let sidebar = ClassroomBrowserViewModel.sidebar(from: classroom)
expect(sidebar.title == classroom.name, "Sidebar title should match classroom name")
expect(sidebar.modules.count == 2, "Sidebar should include scanned modules")
expect(sidebar.modules[0].directLessons.map(\.title) == ["Lesson 2", "Lesson 10"], "Sidebar should map direct lessons")
expect(sidebar.modules[0].categories[0].lessons.count == 2, "Sidebar should map category lessons")
expect(sidebar.warningCount == classroom.warnings.count, "Sidebar should expose warning count")

let defaultsSuite = "LocalClassroomSmokeTests.\(UUID().uuidString)"
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

let viewModelDefaultsSuite = "LocalClassroomViewModelSmokeTests.\(UUID().uuidString)"
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
    expect(viewModel.recentClassrooms.first?.path == root.standardizedFileURL.path, "View model should add opened classrooms to recent storage")

    guard let firstLesson = viewModel.sidebar?.modules[0].directLessons[0] else {
        fatalError("Expected a direct lesson for selection tests")
    }
    viewModel.selectLesson(firstLesson)
    expect(viewModel.selectedLessonPath == "01 Foundations/Lesson 2.mp4", "View model should select lessons")
    viewModel.selectNextLesson()
    expect(viewModel.selectedLessonPath == "01 Foundations/Lesson 10.mp4", "Next lesson should respect visible order")
    viewModel.selectNextLesson()
    expect(viewModel.selectedLessonPath == "01 Foundations/Mindset/Fear.m4v" || viewModel.selectedLessonPath == "01 Foundations/Mindset/Fear.MOV", "Next lesson should move from direct lessons into category lessons")
    viewModel.selectPreviousLesson()
    expect(viewModel.selectedLessonPath == "01 Foundations/Lesson 10.mp4", "Previous lesson should respect visible order")

    let missingRoot = root.deletingLastPathComponent().appendingPathComponent("Missing Classroom", isDirectory: true)
    viewModel.openFolder(missingRoot)
    expect(viewModel.classroom == nil, "Missing classroom should clear the current classroom")
    expect(viewModel.errorMessage != nil, "Missing classroom should produce a recoverable error state")
}

let metadataRoot = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString, isDirectory: true)
let metadataStore = MetadataStore()
let firstMetadataDate = Date(timeIntervalSince1970: 1_800_000_000)
let secondMetadataDate = firstMetadataDate.addingTimeInterval(60)
let thirdMetadataDate = secondMetadataDate.addingTimeInterval(60)

@MainActor func createMetadataFile(_ relativePath: String) throws {
    let url = metadataRoot.appendingPathComponent(relativePath)
    try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data().write(to: url)
}

try createMetadataFile("Module/Alpha.mp4")
let initialMetadataScan = ClassroomScanner().scan(rootURL: metadataRoot)
let initialMetadataResult = metadataStore.loadMergeAndSave(classroom: initialMetadataScan, now: firstMetadataDate)
expect(
    fileManager.fileExists(atPath: metadataStore.metadataURL(rootURL: metadataRoot).path),
    "Missing metadata should create .local-classroom/classroom.json"
)
expect(initialMetadataResult.metadata.schemaVersion == ClassroomMetadata.currentSchemaVersion, "Metadata should use the current schema version")
expect(initialMetadataResult.metadata.lessonState["Module/Alpha.mp4"] == LessonState(), "Unknown scanned lessons should receive default state")

var savedMetadata = initialMetadataResult.metadata
savedMetadata.lessonState["Module/Alpha.mp4"] = LessonState(
    playbackPositionSeconds: 42,
    completed: true,
    lastOpenedAt: firstMetadataDate
)
try metadataStore.save(savedMetadata, rootURL: metadataRoot)
let reloadedSavedMetadata = try metadataStore.load(rootURL: metadataRoot)
expect(reloadedSavedMetadata == savedMetadata, "Metadata writes should read back identically")

try createMetadataFile("Module/Beta.mp4")
let addedLessonResult = metadataStore.loadMergeAndSave(classroom: ClassroomScanner().scan(rootURL: metadataRoot), now: secondMetadataDate)
expect(addedLessonResult.metadata.lessonState["Module/Alpha.mp4"]?.playbackPositionSeconds == 42, "Existing lesson state should be preserved")
expect(addedLessonResult.metadata.lessonState["Module/Beta.mp4"] == LessonState(), "Newly discovered lessons should be added to metadata")

try fileManager.removeItem(at: metadataRoot.appendingPathComponent("Module/Alpha.mp4"))
let missingLessonResult = metadataStore.loadMergeAndSave(classroom: ClassroomScanner().scan(rootURL: metadataRoot), now: secondMetadataDate)
expect(missingLessonResult.metadata.lessonState["Module/Alpha.mp4"]?.missingSince == secondMetadataDate, "Missing lessons should be marked orphaned")

try createMetadataFile("Module/Alpha.mp4")
let restoredLessonResult = metadataStore.loadMergeAndSave(classroom: ClassroomScanner().scan(rootURL: metadataRoot), now: thirdMetadataDate)
expect(restoredLessonResult.metadata.lessonState["Module/Alpha.mp4"]?.missingSince == nil, "Restored lesson paths should recover old state")
expect(restoredLessonResult.metadata.lessonState["Module/Alpha.mp4"]?.playbackPositionSeconds == 42, "Restored lesson paths should preserve playback state")

var orphanedMetadata = restoredLessonResult.metadata
orphanedMetadata.lessonState["Module/Gone.mp4"] = LessonState(
    playbackPositionSeconds: 10,
    completed: false,
    lastOpenedAt: nil,
    missingSince: thirdMetadataDate.addingTimeInterval(-31 * 24 * 60 * 60)
)
try metadataStore.save(orphanedMetadata, rootURL: metadataRoot)
let cleanedMetadataResult = metadataStore.loadMergeAndSave(classroom: ClassroomScanner().scan(rootURL: metadataRoot), now: thirdMetadataDate)
expect(cleanedMetadataResult.metadata.lessonState["Module/Gone.mp4"] == nil, "Orphaned lesson state older than 30 days should be removed")

let malformedRoot = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString, isDirectory: true)
try fileManager.createDirectory(at: malformedRoot.appendingPathComponent("Module", isDirectory: true), withIntermediateDirectories: true)
try Data().write(to: malformedRoot.appendingPathComponent("Module/Lesson.mp4"))
let malformedMetadataDirectory = malformedRoot.appendingPathComponent(MetadataStore.metadataDirectoryName, isDirectory: true)
try fileManager.createDirectory(at: malformedMetadataDirectory, withIntermediateDirectories: true)
try Data("{ nope".utf8).write(to: malformedMetadataDirectory.appendingPathComponent(MetadataStore.metadataFileName))

let malformedResult = metadataStore.loadMergeAndSave(classroom: ClassroomScanner().scan(rootURL: malformedRoot), now: firstMetadataDate)
let malformedBackups = try fileManager.contentsOfDirectory(atPath: malformedMetadataDirectory.path)
    .filter { $0.hasPrefix("classroom.malformed-") }
expect(malformedResult.warnings.contains { $0.kind == .malformedMetadata }, "Malformed metadata should produce a warning")
expect(malformedBackups.count == 1, "Malformed metadata should be backed up")
let recoveredMalformedMetadata = try metadataStore.load(rootURL: malformedRoot)
expect(recoveredMalformedMetadata.lessonState["Module/Lesson.mp4"] != nil, "Classroom should remain usable after malformed metadata recovery")

await MainActor.run {
    let playbackService = PlaybackService()
    let validVideoURL = metadataRoot.appendingPathComponent("Module/Alpha.mp4")
    playbackService.load(url: validVideoURL)
    expect(playbackService.player != nil, "Playback service should initialize a player for an existing local video URL")
    expect(playbackService.currentURL == validVideoURL.standardizedFileURL, "Playback service should retain the current URL")

    playbackService.setPlaybackRate(1.5)
    expect(playbackService.playbackRate == 1.5, "Playback service should store supported playback speed")

    playbackService.load(url: metadataRoot.appendingPathComponent("Module/Missing.mp4"))
    expect(playbackService.player == nil, "Missing video should clear the player")
    expect(playbackService.errorMessage != nil, "Missing video should produce a safe playback error")
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

let progressDefaultsSuite = "LocalClassroomProgressSmokeTests.\(UUID().uuidString)"
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

    guard let alphaLesson = progressViewModel.sidebar?.modules[0].directLessons.first(where: { $0.relativePath == "Module/Alpha.mp4" }) else {
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
    expect(progressViewModel.classroomProgress.percentage == 0.5, "Completion percentage should be correct")
}

let persistedProgressMetadata = try metadataStore.load(rootURL: metadataRoot)
expect(persistedProgressMetadata.lessonState["Module/Alpha.mp4"]?.playbackPositionSeconds == 55, "Playback state should survive metadata reload")
expect(persistedProgressMetadata.lessonState["Module/Alpha.mp4"]?.completed == true, "Completion state should survive metadata reload")

let notesService = NotesService()
let alphaVideoURL = metadataRoot.appendingPathComponent("Module/Alpha.mp4")
let alphaNoteURL = metadataRoot.appendingPathComponent("Module/Alpha.md")
let betaNoteURL = metadataRoot.appendingPathComponent("Module/Beta.md")
let alphaLesson = Lesson(
    relativePath: "Module/Alpha.mp4",
    videoURL: alphaVideoURL,
    notesURL: alphaNoteURL,
    title: "Alpha",
    fileExtension: "mp4"
)

expect(notesService.noteURL(for: alphaVideoURL) == alphaNoteURL, "Note URL should replace the video extension with md")
let missingAlphaNoteText = try notesService.loadNotes(for: alphaLesson)
expect(missingAlphaNoteText == "", "Missing notes should load as empty text")
expect(!fileManager.fileExists(atPath: alphaNoteURL.path), "Missing notes should stay absent until saved")

try notesService.saveNotes("# Alpha\n\nPlain UTF-8 notes.", for: alphaLesson)
expect(fileManager.fileExists(atPath: alphaNoteURL.path), "Saving notes should create the Markdown file")
let savedAlphaNoteText = try notesService.loadNotes(for: alphaLesson)
expect(savedAlphaNoteText == "# Alpha\n\nPlain UTF-8 notes.", "Existing UTF-8 notes should load")

let notesDefaultsSuite = "LocalClassroomNotesSmokeTests.\(UUID().uuidString)"
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

    guard
        let module = notesViewModel.sidebar?.modules.first,
        let alphaSidebarLesson = module.directLessons.first(where: { $0.relativePath == "Module/Alpha.mp4" }),
        let betaSidebarLesson = module.directLessons.first(where: { $0.relativePath == "Module/Beta.mp4" })
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

let orderingRoot = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString, isDirectory: true)
@MainActor func createOrderingFile(_ relativePath: String) throws {
    let url = orderingRoot.appendingPathComponent(relativePath)
    try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data().write(to: url)
}

try createOrderingFile("Module A/Lesson 2.mp4")
try createOrderingFile("Module A/Lesson 10.mp4")
try createOrderingFile("Module A/Category B/Cat Lesson 2.mp4")
try createOrderingFile("Module A/Category A/Cat Lesson 10.mp4")
try createOrderingFile("Module B/Welcome.mp4")

var orderingMetadata = ClassroomMetadata(
    moduleOrder: ["Module B", "Missing Module"],
    categoryOrder: ["Module A": ["Category B", "Missing Category"]],
    lessonOrder: [
        "Module A": ["Lesson 10.mp4", "Missing.mp4"],
        "Module A/Category A": ["Cat Lesson 10.mp4"]
    ]
)
try metadataStore.save(orderingMetadata, rootURL: orderingRoot)

let orderedResult = metadataStore.loadMergeAndSave(classroom: ClassroomScanner().scan(rootURL: orderingRoot), now: firstMetadataDate)
expect(orderedResult.classroom.modules.map(\.name) == ["Module B", "Module A"], "Saved module order should be respected and new modules appended naturally")
expect(orderedResult.classroom.modules[1].categories.map(\.name) == ["Category B", "Category A"], "Saved category order should be respected and new categories appended naturally")
expect(orderedResult.classroom.modules[1].directLessons.map { String($0.relativePath.split(separator: "/").last ?? "") } == ["Lesson 10.mp4", "Lesson 2.mp4"], "Saved direct lesson ordering should be respected")
expect(orderedResult.metadata.moduleOrder == ["Module B"], "Missing module ordering references should be removed during merge")
expect(orderedResult.metadata.categoryOrder["Module A"] == ["Category B"], "Missing category ordering references should be removed during merge")
expect(orderedResult.metadata.lessonOrder["Module A"] == ["Lesson 10.mp4"], "Missing lesson ordering references should be removed during merge")

try createOrderingFile("Module C/New.mp4")
let appendedOrderingResult = metadataStore.loadMergeAndSave(classroom: ClassroomScanner().scan(rootURL: orderingRoot), now: secondMetadataDate)
expect(appendedOrderingResult.classroom.modules.map(\.name) == ["Module B", "Module A", "Module C"], "New modules should append after saved order in natural order")

let orderingDefaultsSuite = "LocalClassroomOrderingSmokeTests.\(UUID().uuidString)"
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
    expect(orderingViewModel.sidebar?.modules.map(\.name) == ["Module B", "Module C", "Module A"], "Moving a module should update only module order")
    orderingViewModel.resetModuleOrder()
    expect(orderingViewModel.sidebar?.modules.map(\.name) == ["Module A", "Module B", "Module C"], "Resetting module order should restore filename order")
    orderingViewModel.moveDirectLesson(moduleID: "Module A", lessonID: "Module A/Lesson 10.mp4", offset: 1)
    expect(orderingViewModel.sidebar?.modules.first?.directLessons.map(\.title) == ["Lesson 2", "Lesson 10"], "Moving direct lessons should update only direct lesson order")
}

let persistedOrderingMetadata = try metadataStore.load(rootURL: orderingRoot)
expect(persistedOrderingMetadata.moduleOrder.isEmpty, "Reset module order should survive metadata reload")
expect(persistedOrderingMetadata.lessonOrder["Module A"] == ["Lesson 2.mp4", "Lesson 10.mp4"], "Direct lesson order should survive metadata reload")

print("LocalClassroomSmokeTests passed")

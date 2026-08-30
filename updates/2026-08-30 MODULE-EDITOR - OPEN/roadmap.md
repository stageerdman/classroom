# Roadmap — MODULE-EDITOR

Seven phases. A–C are Core (non-UI, fully testable without a GUI — this is
where the data-safety-critical logic lives). D–F are the SwiftUI editor
itself. G is tests/docs/build. Each phase builds and, where it has
Core-layer logic, gets real automated coverage before moving on.

Reference: current relevant files —
`Sources/ClassroomCore/Services/{ClassroomScanner,MetadataStore}.swift`,
`Sources/ClassroomCore/Models/ClassroomModels.swift`,
`Sources/ClassroomCore/ViewModels/ClassroomBrowserViewModel.swift`,
`Sources/ClassroomApp/Views/{ClassroomGalleryView,ClassroomBrowserView}.swift`.

---

## Phase A — Metadata migration primitive + raw file tree model

The foundation everything else depends on: a well-tested way to rewrite
metadata keys when something moves, and a model for "everything on disk in
this module," not just what the normal scanner recognizes.

Implement:

- `ClassroomScanner.defaultMediaExtensions` — promote the scanner's private
  extension set to a public static constant so `ClassroomEditorService`
  (Phase B) can reuse it instead of duplicating it.
- `ClassroomNodeKind` enum (`.module`, `.category`, `.lesson`).
- `MetadataMigrationService.migrate(_:kind:oldPath:newPath:) -> ClassroomMetadata`
  — pure function, no I/O. Rewrites `lessonState` keys by path-prefix
  (handles cascading module/category renames). Rewrites `lessonOrder` and
  `categoryOrder` dictionary *keys* by the same prefix rule (relocates a
  renamed category's own lesson-order entry, a renamed module's direct-
  lesson and category-order entries). Rewrites the bare-name *value* inside
  the relevant parent's order array for category rename and lesson
  rename-in-place; drops the stale value (without adding a replacement) when
  a lesson moves to a different parent, letting the existing merge-on-scan
  logic append it naturally in its new location. Rewrites `moduleOrder`'s
  flat array for a module rename.
- `MetadataStore.migratePath(rootURL:kind:oldPath:newPath:) throws` — loads,
  calls the pure function above, saves.
- `FileNode` model (`Identifiable`, recursive `children: [FileNode]`) plus a
  `ModuleFileTree` scanning function (new file, e.g.
  `Services/ModuleFileTreeScanner.swift`) that walks a module folder and
  returns every visible file/folder — including `Attachments/` and any
  `Removed/` folders as ordinary nodes — while still hiding true dotfiles
  (`.lesson`, `.DS_Store`, etc.) and surfacing `isLessonFolder` as a flag
  derived from marker presence rather than as a visible node.

Automated tests (XCTest, `Tests/ClassroomCoreTests`):

- Lesson rename in place (same parent): `lessonState` key rewritten,
  `lessonOrder` value rewritten in place, position preserved.
- Lesson move to a different parent: old parent's order entry dropped,
  `lessonState` key rewritten to the new path, nothing inserted into the new
  parent's order array.
- Category rename: `lessonState` cascades for every contained lesson,
  `lessonOrder`'s key for that category relocates, `categoryOrder`'s bare
  value in the module's array rewrites in place.
- Module rename: cascades into `lessonState`, `lessonOrder` keys,
  `categoryOrder` key, and `moduleOrder`'s bare value.
- `ModuleFileTree` scan surfaces `Attachments/` and `Removed/` as normal
  nodes, hides the `.lesson` marker file itself, and flags marker-bearing
  folders as `isLessonFolder`.

Manual verification: none yet (no UI in this phase).

Exit criterion: metadata migration is correct and independently verified
before anything in the editor UI can rely on it.

---

## Phase B — ClassroomEditorService (Core, file operations)

Implement (new file, `Services/ClassroomEditorService.swift`):

- `transformCandidates(for:) -> TransformCandidates` (media files found,
  notes files found, `isAlreadyLesson`, `hasSubfolders`).
- `transformToLesson(_:chosenMedia:chosenNotes:) throws` — writes the
  `.lesson` marker; moves every other top-level loose file into
  `Attachments/` (created if needed, using the same disambiguation as
  imports below); leaves existing subfolders untouched.
- `createCategory(in:name:) throws -> URL`, `createLesson(in:name:) throws
  -> URL` — validated name (non-empty after trim, no `/` or `:`, no
  collision), creates the folder (+ `.lesson` marker for lessons).
- `rename(_:to:) throws -> URL` — validated name, rejects collision,
  returns the new URL (caller is responsible for the metadata migration
  call using old/new relative paths).
- `move(_:into:) throws -> URL` — reparent, rejects collision at the
  destination, returns the new URL.
- `trash(_:) throws` — `FileManager.trashItem`.
- `importFile(_:into:) throws -> URL` — always a move (per the locked
  decision), auto-disambiguates a colliding destination name with a numeric
  suffix rather than failing.
- `addAttachment(lessonFolderURL:fileURL:) throws -> URL` — creates
  `Attachments/` if needed, delegates to `importFile`.
- `removeAttachment(lessonFolderURL:attachmentURL:) throws` — creates
  `Removed/` if needed, moves the file there.
- `replaceHeroMedia(lessonFolderURL:newMediaURL:) throws` — demotes the
  existing media (if any) into `Attachments/` via `addAttachment`, then
  imports the new file into the lesson folder root.
- `notesLinkMarkdown(for:) -> String` — pure, no I/O: `[name](file://...)`.

Automated tests:

- Transform: single/no media+notes auto-picked; explicit choices honored;
  every other loose file lands in `Attachments/`; existing subfolders
  untouched; disabled/rejected when subfolders are present.
- Create category/lesson: validated names, collision rejected, lesson gets
  the marker.
- Rename: collision rejected, empty/whitespace rejected, `/`/`:` rejected.
- Move: reparent updates the folder location; collision at destination
  rejected.
- Import/attachment-add: name collision produces a numeric-suffixed copy,
  not a failure; always removes the source (move, not copy).
- Remove-attachment: file physically lands in `Removed/`, not deleted.
- Hero replace: old media demoted into `Attachments/` (creating it if
  needed), new media takes its place.

Manual verification: none yet.

Exit criterion: every file operation the editor UI will call is correct and
tested against a real temp-directory filesystem, independent of SwiftUI.

---

## Phase C — Editor view model

Implement (new file,
`ViewModels/ClassroomEditorViewModel.swift`):

- Owns: the module's `FileNode` tree, the structured Category/Lesson outline
  for that module (reuses `ClassroomBrowserViewModel`'s existing
  `sidebar`/ordering plumbing rather than duplicating it), the currently
  open lesson-in-editor (if any), and pending-transform / pending-rename UI
  state.
- Every mutating action (transform, create, rename, move, trash, attachment
  add/remove, hero replace) is: call the `ClassroomEditorService` operation
  → on success, call `MetadataStore.migratePath` if the operation changed a
  relative path → rescan the module's file tree and structured outline →
  surface a clear error message on failure instead of leaving stale state.
- Module rename additionally updates the view model's own "which module am
  I editing" identity so the editor doesn't lose its place.
- `refresh()` — re-scans the raw tree and structured outline on demand.

Automated tests: covered indirectly via the `ClassroomSmokeTests`
executable in Phase G (drives the view model through a realistic sequence:
transform a loose folder, create a category, move a lesson into it, rename
it, remove an attachment, confirm metadata survived every step).

Exit criterion: the view model is a thin, correctly-ordered orchestration
layer over Phase A/B services — no file-system logic duplicated here.

---

## Phase D — Editor entry point and shell

Implement:

- Right-click context menu on a module card in `ClassroomGalleryView` →
  "Open as Editor."
- New `ModuleEditorView` (sheet), two-pane `HSplitView`: raw tree (left),
  structured outline (right). Header: module name (inline-editable) and
  description (inline-editable, autosaved via the existing `NotesService`
  raw-URL save path against `description.md`). Done/close button.
- Wire into `ClassroomBrowserView`/`ClassroomGalleryView` as a `.sheet`
  presentation driven by a new `editingModuleID` piece of state — kept
  separate from `selectedModuleID` (normal browsing) since the two are
  mutually exclusive entry points from the gallery.

Manual verification:

- Right-click a module, open the editor, confirm it shows that module's
  real folder contents including any stray files the normal browser
  ignores. Rename the module and its description; confirm both persist
  after closing and reopening the editor.

Exit criterion: the editor opens, shows real data, and closes cleanly.

---

## Phase E — Structured outline: reorder, reparent, create, transform

Implement:

- Drag-to-reorder within the structured outline (reuses the existing
  `moveCategory`/`moveDirectLesson`/`moveCategoryLesson`-style ordering
  calls already on `ClassroomBrowserViewModel`).
- Drag-to-reparent a Lesson row across categories/direct-lessons — calls
  `ClassroomEditorViewModel`'s move action.
- **+** buttons to create a Category or Lesson, entering inline rename
  immediately (Finder-style).
- Right-click on a raw-tree folder → "Transform to Lesson," including the
  disambiguation sheet when there's more than one media/notes candidate;
  disabled when the folder has subfolders or is already a lesson.
- Right-click on any structured-outline item → Rename, Trash.

Manual verification:

- Reorder categories and lessons by drag; confirm it survives reopening.
- Drag a lesson from one category into another; confirm its saved
  completion/progress state is still attached afterward.
- Create a new category and lesson via **+**, rename them inline, drag them
  into position.
- Transform a loose folder with two videos and one `.md` file: confirm the
  picker appears for the video, the `.md` is auto-picked, and the third
  loose file (if any) lands in `Attachments/`.

Exit criterion: full structural editing works end-to-end through the UI.

---

## Phase F — Lesson panel: three drop zones, attachments, Trash

Implement:

- Selecting a lesson in the structured outline opens its detail panel
  within the editor: hero drop zone, notes text view (drop inserts a
  Markdown link, no file movement), attachments list.
- Attachments list: each row draggable out to Finder (`.draggable(url)`);
  **X** button moves it to `Removed/`.
- Hero zone: drop replaces media, demotes the old file to `Attachments/`.
- All three zones accept drags from Finder and from the editor's own raw
  tree.
- Refresh action in the editor toolbar (reuses the existing rescan
  pipeline) to pick up out-of-band changes like a drag-to-Finder move.

Manual verification:

- Drop a video from Finder onto the hero zone; confirm the old video is now
  listed under Attachments.
- Drop a file onto the notes text area; confirm a Markdown link appears and
  the original file did not move.
- Drop a file onto Attachments; confirm it appears in the list and physically
  lives in `Attachments/`.
- Remove an attachment via **X**; confirm it disappears from the normal
  attachments list but is visible in the editor's raw tree under `Removed/`.
- Drag an attachment out to the Finder desktop; confirm the file physically
  relocates there and disappears from the lesson after a refresh.

Exit criterion: all three drop zones and the attachment lifecycle work as
specified.

---

## Phase G — Tests, docs, build verification

Implement:

- `Tests/ClassroomCoreTests`: the Phase A/B unit tests described above.
- `Tests/ClassroomSmokeTests/main.swift`: an end-to-end sequence exercising
  `ClassroomEditorViewModel` — transform, create, move, rename, attachment
  add/remove, hero replace — asserting metadata (completion/progress/order)
  survives every step.
- `docs/phase-9-checklist.md`: manual verification checklist consolidating
  Phases D–F's manual steps above.
- `README.md`: note the editor entry point and the `Removed/` convention
  alongside the existing structure section.
- Full verification pass: `swift build`, `swift test`, `swift run
  ClassroomSmokeTests`, rebuild `Classroom.app` via
  `scripts/create-launcher-app.sh`.
- Close the update: flip `OPEN` → `CLOSED`, final summary pass on
  `update.md`.

Exit criterion: green build/tests, docs describe the shipped behavior,
launcher rebuilt and confirmed non-stale.

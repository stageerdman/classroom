# Roadmap — GALLERY-LESSON-FOLDERS

Six phases, one at a time, each built/tested/manually-verified before the
next starts (per `CLAUDE.md`). Phases A–B rebuild the ground truth (what a
Lesson *is*); phases C–D rebuild navigation on top of that ground truth;
phase E adds the attachments surface the new structure unlocks; phase F is
tests/fixtures/docs/build cleanup across the whole update.

Reference: current relevant files —
`Sources/LocalClassroomCore/Models/ClassroomModels.swift`,
`Sources/LocalClassroomCore/Services/ClassroomScanner.swift`,
`Sources/LocalClassroomCore/Models/ClassroomMetadata.swift`,
`Sources/LocalClassroomCore/ViewModels/ClassroomBrowserViewModel.swift`,
`Sources/LocalClassroomApp/Views/{ClassroomBrowserView,ClassroomSidebarView,HomeView}.swift`,
`Sources/LocalClassroomApp/LocalClassroomApp.swift`.

---

## Phase A — Lesson-folder scanning

Replace "a lesson is a video file" with "a lesson is a folder marked by a
hidden `.lesson` marker file" in the scanner and models. This is the
foundational change everything else depends on.

Implement:

- `Lesson` model (`ClassroomModels.swift`) reshaped: `relativePath` now
  identifies the *folder*, not a video file. Add `mediaURL: URL?` (the
  resolved playable file, if present), `notesURL: URL?` (the resolved `.md`
  file, if present), `attachmentURLs: [URL]` (contents of `Attachments/`, if
  present and non-empty).
- Widen the playable-file extension set beyond `mp4/mov/m4v` to cover audio
  (`mp3`, `m4a`, `wav` at minimum) — "video, mp3, any format like that" per
  the request. Keep it a configurable `Set<String>` on `ClassroomScanner`
  like today's `supportedVideoExtensions`, just renamed/broadened to
  `supportedMediaExtensions`.
- Scanner logic: a directory is a **Lesson** iff it directly contains the
  `.lesson` marker file. A directory without the marker is a **Category**
  (or the Module itself). Within a Lesson folder: pick at most one file
  matching `supportedMediaExtensions` as `mediaURL`, at most one `.md` file
  as `notesURL`, and an `Attachments` subfolder (case-sensitive match, TBD
  during implementation whether to case-fold) whose visible files become
  `attachmentURLs`. Anything else inside a Lesson folder is ignored (mirrors
  today's "files other than supported videos and matching notes are
  ignored" rule).
- Warnings: add new `ClassroomWarning.Kind` cases for a Lesson folder with
  more than one media file, more than one `.md` file, or neither — surfaced,
  not fatal, matching the existing warning-not-error philosophy.
- `ClassroomModule.description: String?` populated by reading
  `description.md` directly inside the module folder, if present.
- Remove the old "videos directly in a directory become lessons" path
  entirely — no dual-mode scanning. This is the breaking change from
  `update.md`.

Automated tests (`Tests/LocalClassroomCoreTests`):

- new fixture trees: lesson folder with marker + media + notes; marker-only
  (no media/notes); media without marker (must NOT be treated as a lesson);
  Attachments present with files; Attachments present but empty (no
  attachments surfaced); module with/without `description.md`; direct
  lesson folder under Module; lesson folder under Category.
- old-format fixtures (flat video+md) now assert they produce **no**
  lessons (confirms the breaking change is intentional, not a regression).

Manual verification:

- Point the dev scanner screen (`DeveloperScannerView`) at a hand-built
  fixture folder on disk using the new structure; confirm the printed
  hierarchy matches expectations, including attachments and description
  detection.

Exit criterion: scanner and models fully describe the new structure; no UI
depends on the old shape yet (next phases wire that up).

---

## Phase B — Metadata adaptation

Adjust metadata handling for the new Lesson identity key and confirm the
"no auto-migration" behavior is clean rather than silently corrupting state.

Implement:

- Confirm `MetadataStore` keys (`lessonState`, `lessonOrder`, etc.) key off
  `Lesson.relativePath` as already designed — since that now points at a
  folder path instead of a file path, no key-shape change is needed, but
  bump `schemaVersion` handling/tests to make sure old metadata against a
  restructured classroom degrades the way the spec's orphan rules already
  describe (unmatched keys just don't merge against anything and eventually
  age out) rather than erroring.
- No changes needed to attachments in metadata — attachments are derived
  live from the filesystem each scan, never persisted.

Automated tests:

- old-format `classroom.json` loaded against a new-format classroom
  produces zero crashes and zero incorrectly-matched lesson state (keys
  don't collide).
- new-format lesson state round-trips (save progress/completion, rescan,
  confirm it's still attached to the right lesson folder).

Manual verification:

- Restructure a real Phase-A-era test classroom into the new folder format,
  reopen it, confirm it opens cleanly with fresh (not corrupted) state.

Exit criterion: metadata layer is inert with respect to the format change —
it neither crashes nor silently misattributes old state to new lessons.

---

## Phase C — Classroom gallery view

Build the new top-level "big blocks of modules" view and the module-scoped
navigation that replaces today's always-visible sidebar.

Implement:

- New `ClassroomGalleryView` (SwiftUI, `LocalClassroomApp/Views/`): grid of
  module cards, no sidebar, no progress chrome at this level. Each card:
  bold module name, `description` text under it (omitted entirely if nil),
  and a progress indicator sourced from the existing
  `ProgressService.moduleProgress`.
- New navigation state: "classroom open, no module selected" (gallery) vs.
  "module selected" (today's sidebar+player layout, scoped to that module).
  This is a view-model concern — likely a `selectedModuleID` published
  property on `ClassroomBrowserViewModel` (or a small dedicated
  `ClassroomNavigationViewModel` if the existing view model is getting hard
  to hold in your head — split it out per the modularization principle
  rather than bolting more state onto an already-large view model).
- `ClassroomSidebarView` becomes module-scoped: when a module is selected,
  it shows that module's categories/direct-lessons only (not every module in
  the classroom), plus a "back to modules" affordance.
- `ClassroomBrowserView` becomes a router between `ClassroomGalleryView` and
  the existing sidebar+detail layout based on navigation state.
- `HomeView` simplifies to the true empty state described in the request —
  when no classroom is open, no sidebar, no embedded recents list, just an
  "Open a Classroom" affordance. (Recents move to the File menu in Phase D.)

Automated tests:

- view-model tests: opening a classroom lands in gallery state; selecting a
  module transitions to module state with the right scoped sidebar content;
  navigating back clears module selection without losing classroom state;
  switching classrooms resets to gallery state.

Manual verification:

- Open a multi-module classroom; confirm the gallery (not the sidebar) is
  the first thing shown; confirm no progress bar/sidebar leaks through at
  this level; open a module, confirm sidebar/player/notes appear scoped to
  it; navigate back to the gallery and into a different module.

Exit criterion: gallery is the default classroom view; sidebar is reachable
only inside a module and only shows that module's contents.

---

## Phase D — Recents move to File → Open Recent

Implement:

- Remove the `Section("Recent")` block from `ClassroomSidebarView`.
- In `LocalClassroomApp.swift`, add a `CommandGroup` (or `CommandMenu`)
  presenting `RecentClassroomStore.list()` as a submenu of File, each item
  posting the same open-recent action `ClassroomBrowserViewModel.openRecent`
  already implements — this is a UI relocation, not new recents logic.
- Menu needs to reflect store state dynamically (recent list changes as
  classrooms are opened/removed) — likely means the command group reads
  from a shared observable rather than a one-time snapshot; confirm SwiftUI
  `.commands` re-renders on published changes from the app's root state.

Automated tests:

- `RecentClassroomStore` tests are already in place (add/remove/dedupe) and
  don't need to change — this phase is purely wiring existing store data
  into a new UI location.

Manual verification:

- Open several classrooms, confirm they appear under File → Open Recent in
  most-recent-first order; remove one, confirm it drops off the menu;
  confirm no recents list is visible anywhere in the main window.

Exit criterion: recents are reachable exclusively via the File menu.

---

## Phase E — Attachments surface

Implement:

- `AttachmentsSectionView` (or inline section in the lesson detail view):
  rendered at the bottom of the lesson, below notes, only when
  `lesson.attachmentURLs` is non-empty — entirely absent otherwise, per the
  request.
- Each attachment opens via `NSWorkspace.shared.open(url)` (or reveal-in-
  Finder as a secondary action, consistent with existing "reveal in Finder"
  patterns if any exist elsewhere in the app).

Automated tests:

- view-model exposes attachments for the selected lesson correctly
  (present/absent cases already covered by Phase A scanner tests; this
  phase's tests focus on the selected-lesson → attachments wiring).

Manual verification:

- Lesson with an `Attachments/` folder containing 2+ files: confirm section
  appears at the bottom, confirm each file opens.
- Lesson without `Attachments/` (or with an empty one): confirm no section
  renders at all.

Exit criterion: attachments are visible and openable exactly when present.

---

## Phase F — Fixtures, docs, and build verification

Implement:

- Replace/extend `Tests/LocalClassroomCoreTests` fixtures wholesale for the
  new structure (marker files, media+notes+Attachments combinations,
  description.md) — old flat-lesson fixtures either removed or repurposed
  specifically to assert the breaking change.
- New `docs/phase-<n>-checklist.md` covering this update's manual
  verification steps in the same format as existing phase checklists, so
  future updates can reference it the way `update.md` (INIT) references
  phases 0–7.
- `README.md` update if the classroom folder structure section documents
  the old lesson format (video+sibling md) — needs to reflect Lesson
  folders, the `.lesson` marker, `Attachments/`, and `description.md`.
- `local_classroom_codex_spec.md` is the original spec document — leave it
  as historical baseline, but note in `update.md`'s "why" that this update
  deliberately diverges from Section 3 of that spec.
- Full verification pass: `swift build`, `swift test`,
  `swift run LocalClassroomSmokeTests`, rebuild `Local Classroom.app` via
  `scripts/create-launcher-app.sh`, manual checklist end to end.
- Close the update: flip folder suffix `OPEN` → `CLOSED`, final summary pass
  on `update.md`.

Exit criterion: green build/tests, docs describe the shipped behavior, app
launcher rebuilt and confirmed non-stale before calling this update done.

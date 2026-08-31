# MODULE-EDITOR-GHOST-BROWSING

**Status:** CLOSED
**Opened:** 2026-08-31
**Closed:** 2026-08-31

## Goal

Follow-up to `2026-08-30 MODULE-EDITOR`, filed after real-world testing on
the Tony Robbins CORE 100 module. Two problems surfaced:

1. **False "contains subfolders" rejection.** "Transform to Lesson" on a
   folder with no real subfolders (or only an `Attachments`-style folder)
   was being rejected, because the old check blocked on *any* subfolder at
   all rather than only on a subfolder that's itself a real lesson.
2. **Ghost folders were dead ends.** A ghost folder (an unmarked subfolder
   discovered under a category) showed up in the sidebar but couldn't be
   expanded — there was no way to see what was inside it or move files
   between folders while reorganizing.

## What shipped

- `ClassroomEditorService.transformCandidates(for:)` — `hasSubfolders` now
  only counts subfolders that are themselves marked as a real lesson
  (`.lesson` file present). A folder containing an `Attachments` folder, a
  `Removed` folder, or any other unmarked subfolder is now a valid
  transform target; those subfolders are left untouched (or, for
  `Attachments`/`Removed`, already read correctly by the scanner) and
  surface as ghosts inside the new lesson afterward, matching how
  `lessonGhostEntries` already treats them. Only a subfolder that's a real
  lesson still blocks the transform — that's the actual signal the folder
  is functioning as a Category, which was the original intent of the
  guard.
- `ClassroomEditorService.EditorError.hasSubfolders`'s user-facing message
  updated to match: "This folder already contains a lesson, so it can't be
  transformed directly."
- `ClassroomBrowserViewModel.ghostEntries(inFolderURL:)` — a URL-based
  ghost listing (no known-names exclusion, since nothing below a ghost
  folder is ever part of the recognized structure) so a ghost folder's
  contents can be listed on demand.
- `ClassroomBrowserViewModel.moveGhost(atAbsolutePath:toCategoryID:)` /
  `moveGhost(atAbsolutePath:intoFolderURL:)` — moves a ghost file or folder
  (identified by absolute path, since ghosts have no relative-path
  identity) into a recognized category/module root or into another ghost
  folder. Plain `ClassroomEditorService.move`, no metadata migration needed
  since nothing with saved state can be a ghost.
- New `GhostEntryRow` view (`Sources/ClassroomApp/Views/GhostEntryRow.swift`)
  — replaces the old flat, non-expandable ghost row. A ghost folder is now
  a `DisclosureGroup` whose children are computed live via
  `ghostEntries(inFolderURL:)`, recursively, so nested ghost folders can be
  opened arbitrarily deep. Both files and folders are `.draggable` with a
  `"ghost-path:"`-prefixed absolute path; ghost folders are also drop
  targets. `ClassroomSidebarView.handleReparentDrop` now checks for that
  prefix to route a drop to `moveGhost` instead of the existing
  lesson-reparent `moveLesson` path, so the same drag-and-drop mechanism
  used for lessons now also moves loose files/folders around during
  editing.

## Verification

- `swift build` — clean.
- `swift run ClassroomSmokeTests` — passed, extended with: a nested ghost
  folder's contents surfacing via `ghostEntries(inFolderURL:)`, and a ghost
  file being moved (via `moveGhost`) out of a nested ghost folder into a
  recognized category, confirmed present at the new location and gone from
  the old one.
- `swift test` — compiles; no `xctest` runner in this sandbox (same
  standing note as prior updates — run for real on a machine with Xcode).
  `ClassroomEditorServiceTests` updated: the old
  "rejected when it has subfolders" test now marks the nested subfolder as
  a real lesson (matching the corrected semantics) and a new test confirms
  a plain unmarked subfolder and a pre-existing `Attachments` folder no
  longer block the transform.
- Not exercised visually in this session (no way to drive a macOS GUI from
  here): the recursive disclosure UI, drag-and-drop feel for ghost items,
  and the "Transform to Lesson" context menu on nested ghost folders. Build
  and smoke tests are clean and the underlying service/view-model calls
  are covered directly; confirm the interaction itself by hand on the
  CORE 100 module.

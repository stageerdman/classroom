# LESSON-EXPANSION-SHOW-EVERYTHING

**Status:** CLOSED
**Opened:** 2026-08-31
**Closed:** 2026-08-31

## Goal

Second correction to lesson browsing, same day as
`2026-08-31 LESSON-SIDEBAR-EXPANSION`. That update gave lesson rows a
disclosure triangle, but feedback: "I still don't see files and folders
even after I open it, like there's no attachments folder or file.md."

Root cause: expanding a lesson row called
`ClassroomBrowserViewModel.ghostEntries(forLessonID:)`, which used
`ClassroomEditorService.lessonGhostEntries` — a listing that deliberately
*excludes* the lesson's chosen media, chosen notes, and `Attachments`/
`Removed` folders (that method exists so the old "Other Files In This
Lesson" panel only showed genuinely leftover files, since the recognized
ones were already shown elsewhere in the detail pane). But that panel is
gone now (removed in the prior update) — and the ask from the start was
to open a lesson "the same way I'm opening the ghost folders," which show
*everything* inside a folder, nothing excluded. The exclusion logic that
made sense for the old panel was actively wrong for the new disclosure
mechanism.

## What shipped

- `ClassroomSidebarView.lessonGhosts(_:)` now calls
  `viewModel.ghostEntries(inRelativePath:excludingNames:)` — the same
  generic, nothing-excluded listing used for ghost folders — instead of
  the lesson-specific exclusion-based one. Expanding a lesson row now
  shows its media file, its notes `.md`, `Attachments/`, `Removed/`, and
  anything else, exactly like opening a ghost folder does. `Attachments/`
  itself is then a ghost folder you can open to see what's inside it.
- Removed `ClassroomBrowserViewModel.ghostEntries(forLessonID:)` and
  `ClassroomEditorService.lessonGhostEntries` — both now fully unused;
  deleted rather than left as dead code (the "recognized vs. leftover"
  distinction they encoded no longer has a caller now that lesson
  browsing shows everything unconditionally).

## Verification

- `swift build` — clean.
- `swift run ClassroomSmokeTests` — passed; the lesson-ghost check now
  asserts the lesson's *own recognized media file* shows up in the
  listing (previously it would have been excluded), alongside the
  already-covered stray file — the two things that together prove nothing
  is being filtered out anymore.
- `swift test` — compiles; `ClassroomEditorServiceTests`'s dedicated
  lesson-exclusion test replaced with one confirming
  `ghostEntries(in:excludingNames: [])` returns literally everything
  (media, notes, Attachments, Removed, an extra folder) for a lesson
  folder. No `xctest` runner in this sandbox, same standing note.
- **Not verified in this session** (no GUI here): actually expanding a
  lesson row in the running app and seeing Attachments/notes/media listed.

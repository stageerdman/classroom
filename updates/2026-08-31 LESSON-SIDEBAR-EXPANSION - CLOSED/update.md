# LESSON-SIDEBAR-EXPANSION

**Status:** CLOSED
**Opened:** 2026-08-31
**Closed:** 2026-08-31

## Goal

Correction to `2026-08-31 LESSON-FILES-MEDIA-MARKDOWN`. That update made a
lesson's stray files browsable, but put them in a detail-pane section
("Other Files In This Lesson") you only saw after selecting the lesson.
Feedback: that's not what was asked for — "I don't wanna see no Other
Files In This Lesson section, I just need to open it the same way I'm
opening the ghost folders while I'm in edit mode." The ask was for a
lesson row itself to behave exactly like a ghost folder row: a disclosure
triangle in the sidebar, no separate panel, no need to select it first.

## What shipped

- Removed the "Other Files In This Lesson" section from
  `ClassroomBrowserView`'s detail pane entirely, along with the
  `lessonGhostsSection` view and `ClassroomBrowserViewModel
  .ghostEntriesForSelectedLesson()` that fed it.
- Every lesson row in `ClassroomSidebarView` (both a module's direct
  lessons and a category's lessons) now expands, while editing, via the
  same `DisclosureGroup` + `GhostEntryRow` mechanism already used for
  ghost folders — `allowsTransform: false`, same as before, since a
  folder inside a lesson still can't become a nested lesson. Not
  editing: completely unchanged, no disclosure triangle, matching the
  "must look exactly as when you open the module" rule from the original
  MODULE-EDITOR update.
- New `lessonSidebarRow(_:)` replaces the old pattern of attaching
  `.contextMenu` at the `ForEach` call site directly to `lessonRow(...)`;
  it now branches on `isEditingModule` and, when editing, wraps
  `lessonRow(lesson).contextMenu { ... }` as the `DisclosureGroup`'s
  *label* — not the group itself — for the same reason categories and
  ghost folders already do this: attaching interaction modifiers to the
  whole group instead of the label lets a click/drag on a nested ghost
  row get misattributed to the lesson.
- `ClassroomBrowserViewModel.ghostEntries(forLessonID:)` replaces
  `ghostEntriesForSelectedLesson()` — takes a lesson ID directly rather
  than reading `selectedLesson`, so a sidebar row can ask for its own
  ghosts without the lesson being selected at all.

## Verification

- `swift build` — clean.
- `swift run ClassroomSmokeTests` — passed; the existing lesson-ghost
  smoke coverage now calls `ghostEntries(forLessonID:)` directly (and
  explicitly asserts the lesson isn't yet selected when it's called, to
  prove there's no hidden dependency on selection).
- `swift test` — compiles; no `xctest` runner in this sandbox.
- **Not verified in this session** (no way to drive a macOS GUI here):
  the actual disclosure-triangle interaction on a lesson row, that
  clicking the row still selects the lesson independently of expanding
  it, and that drag/drop out of an expanded lesson row still works. Run
  through the manual checklist by hand.

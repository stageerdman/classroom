# Phase 8 Checklist — Classroom Gallery & Lesson Folders

Tracks the `2026-08-30 GALLERY-LESSON-FOLDERS` update: see
`updates/2026-08-30 GALLERY-LESSON-FOLDERS - OPEN/update.md` for the full
rationale. This is a breaking format change — classrooms using the old flat
`Lesson Name.mp4` + `Lesson Name.md` pairing are not migrated automatically.

## Scope

- Lessons are folders, identified by a hidden `.lesson` marker file, not by
  "contains a video file." A Lesson folder can sit directly under a Module
  or inside a Category folder.
- A Lesson folder holds at most one playable media file (video or audio —
  `mp4`, `mov`, `m4v`, `mp3`, `m4a`, `wav`), at most one `.md` notes file,
  and an optional `Attachments/` folder whose contents are exposed as
  openable attachments.
- A Module folder may contain an optional `description.md`; its contents
  become the module's gallery card description.
- Opening a classroom shows a gallery grid of module cards (bold name,
  description, progress) with no sidebar and no progress chrome.
- Opening a module reveals the sidebar (categories/lessons scoped to that
  module) and the existing player/notes/attachments detail pane.
- Recent classrooms moved out of the sidebar into File → Open Recent.
- Attachments render at the bottom of the lesson detail view, only when the
  lesson has at least one attachment.

## Automated Verification

- `swift build`
- `swift test`
- `swift run LocalClassroomSmokeTests`

## Manual Verification

- Run `swift run LocalClassroom` or open `Local Classroom.app`.
- Build a fixture classroom on disk using the new structure: a module with
  `description.md`, a direct lesson folder (marker + media + notes), a
  category folder containing a lesson folder with an `Attachments/` folder,
  and a lesson folder with no media (notes-only).
- Open the classroom folder: confirm the gallery (not the sidebar) is the
  first thing shown, with module name/description/progress on each card and
  no sidebar or progress chrome visible at this level.
- Click a module card: confirm the sidebar appears scoped to that module's
  categories/lessons, and the player/notes pane behaves as before.
- Select the notes-only lesson: confirm no player area renders and no error
  is shown.
- Select the lesson with attachments: confirm an "Attachments" section
  appears at the bottom and each attachment opens; select a lesson without
  attachments and confirm the section is absent entirely.
- Use the sidebar "back" control to return to the gallery, then open a
  different module.
- Use File → Open Recent to reopen a previously opened classroom; confirm
  no recents list is visible anywhere in the main window.
- Point the app at an old-format classroom (flat video + sibling `.md`,
  no `.lesson` marker folders) and confirm it opens with zero lessons
  rather than crashing — this is the expected breaking-change behavior.

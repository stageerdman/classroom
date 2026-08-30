# Phase 9 Checklist — Module Editor

Tracks the `2026-08-30 MODULE-EDITOR` update: see
`updates/2026-08-30 MODULE-EDITOR - CLOSED/update.md` for the full
rationale. This UI was built without any way to drive a macOS GUI in the
build environment — automated coverage exercises every underlying
operation (transform, create, rename, move, import, attachment lifecycle,
metadata migration) against a real filesystem, but the drag-and-drop
interactions themselves need a real run-through before trusting them.

## Scope

- "Open as Editor" on a module card's right-click menu in the gallery.
- Two-pane editor: raw file/folder tree (left) and structured Category/
  Lesson outline (right), scoped to the one module that was opened.
- Transform to Lesson on a plain folder, including the disambiguation
  sheet for multiple media/notes candidates, and archiving every other
  loose file into `Attachments/`.
- Create Category/Lesson via **+**, drag-to-reorder, drag-to-reparent a
  lesson across categories, inline rename, Move to Trash.
- Lesson detail panel: hero media drop zone (replaces media, demotes the
  old file to `Attachments/`), notes drop zone (inserts a Markdown link,
  moves nothing), attachments drop zone (adds) with **X** removal (moves
  to a lesson-local `Removed/` folder, never deletes).
- Module name and description, editable directly in the editor header.

## Automated Verification

- `swift build`
- `swift test`
- `swift run ClassroomSmokeTests`

## Manual Verification

- Run `swift run Classroom` or open `Classroom.app`.
- Right-click a module card in the gallery → **Open as Editor**. Confirm
  the raw tree shows every real file/folder in that module, including
  anything the normal browser would ignore.
- Rename the module and edit its description from the editor header;
  close the editor, reopen it, confirm both persisted; confirm the
  gallery card reflects the new name/description after closing.
- Right-click a plain folder containing two videos and one `.md` file in
  the raw tree → **Transform to Lesson**: confirm the picker appears for
  the video, the lone `.md` is auto-picked, and the leftover video lands
  in that lesson's `Attachments/`.
- Right-click a plain folder that already has subfolders: confirm
  **Transform to Lesson** doesn't appear (or is disabled).
- Create a new Category and a new Lesson via **+**; rename them inline;
  drag them to reorder.
- Drag a lesson from one category into another (or into the direct-lesson
  section): confirm it moves on disk and its saved completion/progress
  state (check via normal browsing) is still attached afterward.
- Move to Trash a Category: confirm it's recoverable from the actual
  macOS Trash, and that the classroom no longer shows it after refresh.
- Select a lesson in the structured outline: confirm the detail panel
  shows its current media, notes, and attachments.
- Drop a video from Finder onto the hero zone: confirm the old video (if
  any) now appears under Attachments, and the new one plays as the hero.
- Drop a file onto the notes area: confirm a Markdown link is inserted
  and the source file did not move from its original location.
- Drop a file onto the attachments zone: confirm it appears in the list
  and physically lives in that lesson's `Attachments/` folder.
- Remove an attachment via **X**: confirm it disappears from the normal
  attachments list but is visible in the editor's raw tree under
  `Removed/`, and is invisible in normal (non-editor) browsing.
- Drag an attachment out of the editor onto the Finder desktop: confirm
  the file physically relocates there; after pressing Refresh in the
  editor, confirm it's gone from the lesson.
- Open a second module's editor after making changes in the first;
  confirm no cross-module leakage (the raw tree and outline are scoped to
  the module you opened).
- Close the editor and confirm the gallery/module browsing view reflects
  every structural change made inside it.

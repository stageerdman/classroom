# Phase 9 Checklist — Module Editing

Tracks the `2026-08-30 MODULE-EDITOR` update and its
`2026-08-31 MODULE-EDITOR-GHOST-BROWSING` follow-up: see those updates'
`update.md` for full rationale, including why the first version of this (a
separate two-pane editor screen) was scrapped in favor of editing in
place, and why "Transform to Lesson" and ghost-folder browsing were
revised after real-world testing. This UI was built without any way to
drive a macOS GUI in the build environment — automated coverage exercises
every underlying operation (transform, create, rename, move, import,
attachment lifecycle, metadata migration) against a real filesystem, but
the drag-and-drop interactions themselves need a real run-through before
trusting them.

## Scope

- Editing is not a separate screen. The exact same sidebar
  (`ClassroomSidebarView`) and detail pane (`ClassroomBrowserView`'s
  player/notes/attachments) render identically whether or not editing is
  on — editing only adds inline affordances on top.
- Entry points: right-click a module card in the gallery → **Open as
  Editor** (opens the module with editing already on), or the **Edit**
  toggle in an already-open module's sidebar.
- While editing: inline rename (module name/description, categories,
  lessons), **+** to create a category or lesson, drag-to-reorder (same
  mechanism as before editing existed), drag-to-reparent a lesson across
  categories, Transform to Lesson on a category, Move to Trash on a
  category or lesson.
- Lesson detail pane while editing: media area accepts a drop to replace
  the hero media (old file moves to `Attachments/`); notes area accepts a
  drop to insert a Markdown link (nothing moves); attachments section
  accepts drops to add and shows an **X** per attachment to remove it
  (moves to that lesson's `Removed/` folder, never deletes).
- **Ghost entries**: while editing, anything on disk not part of the
  recognized structure — a loose file next to a category, an unmarked
  folder one level too deep inside a category, or an extra file inside a
  lesson folder — renders as a dimmed, italic row alongside the real ones,
  at module, category, and lesson level respectively. A ghost folder
  inside a category can be transformed into a lesson from its context
  menu. Ghost folders expand (disclosure triangle) to show their own
  contents recursively, however deep — nothing on disk is a dead end. A
  ghost file or folder can be dragged into another category or ghost
  folder to move it on disk, the same drag mechanism used for lessons.
- **Transform to Lesson** only rejects a folder if one of its subfolders is
  itself a real lesson (i.e. the folder is genuinely functioning as a
  Category). A folder with an `Attachments` folder, a `Removed` folder, or
  any other unmarked subfolder is a valid transform target — those
  subfolders are left alone and surface as ghosts inside the new lesson.

## Automated Verification

- `swift build`
- `swift test`
- `swift run ClassroomSmokeTests`

## Manual Verification

- Run `swift run Classroom` or open `Classroom.app`.
- Open a module normally (no editing) and confirm the sidebar and detail
  pane look exactly as before this update — no new buttons, fields, or
  chrome visible anywhere.
- Right-click a module card in the gallery → **Open as Editor**: confirm
  it opens straight into that module with the **Edit**/pencil button
  already toggled on, and the module name/description are now editable
  text fields in the sidebar header.
- Toggle **Edit** off and on from inside an already-open module; confirm
  the layout never jumps or changes size, only the inline affordances
  appear/disappear.
- Rename the module, a category, and a lesson inline; confirm each
  persists after toggling edit mode off and back on.
- Create a new category and a new lesson via the **+** rows; confirm they
  appear immediately and are draggable like any other row.
- Reorder lessons/categories by drag; confirm it persists (same ordering
  system as before this update, unchanged).
- Drag a lesson from the direct-lessons area into a category (drop on the
  category's row), and from one category to another; confirm it moves on
  disk and its saved completion/progress state is still attached
  afterward (check by turning edit mode off and reselecting the lesson).
- Right-click a category with only loose files inside (no marker) →
  **Transform to Lesson**: for a folder with two videos and one `.md`
  file, confirm the picker sheet appears for the video, the lone `.md` is
  auto-picked, and the leftover video lands in `Attachments/`.
- Move a category to Trash; confirm it's recoverable from the actual
  macOS Trash and disappears from the sidebar.
- Select a lesson while editing: drop a video from Finder onto the media
  area — confirm the old video (if any) now appears under Attachments and
  the new one plays as the hero.
- Drop a file onto the notes area: confirm a Markdown link is inserted
  and the source file did not move from its original location.
- Drop a file onto the attachments drop zone: confirm it appears in the
  list and physically lives in that lesson's `Attachments/` folder.
- Remove an attachment via **X**: confirm it disappears from the
  attachments list; turn editing off and on for a fresh look — it should
  stay gone (it's now in `Removed/`, not deleted).
- Toggle **Edit** off, then back on for a different module — confirm no
  state leaks between modules (fresh module name/description fields,
  fresh selection).
- Drop a stray file directly into a module folder in Finder (sibling to
  its category/lesson folders) while the app is open; toggle editing on
  and Refresh — confirm it appears as a dimmed "ghost" row, and that it
  disappears the instant editing is turned off.
- Create an unmarked subfolder one level too deep inside a category in
  Finder; confirm it shows as a dimmed ghost folder row inside that
  category (not just a warning), and that its context menu offers
  **Transform to Lesson**; use it and confirm the folder becomes a real,
  selectable lesson.
- Put a file inside that unmarked subfolder (before transforming it);
  confirm the ghost folder row has a disclosure triangle, and clicking it
  reveals the file as a nested ghost row. Nest another unmarked folder
  inside that one with its own file and confirm it opens too, arbitrarily
  deep.
- Drag a ghost file out of a nested ghost folder and drop it onto a
  category row (or another ghost folder); confirm it physically moves on
  disk to the destination and disappears from its old location.
- Create a folder with just an `.md` file and an already-existing
  `Attachments` subfolder (containing a random file) in Finder; confirm
  right-click → **Transform to Lesson** succeeds (does *not* say the
  folder contains subfolders) and the `Attachments` folder's contents are
  still there afterward, listed as the lesson's attachments.
- Create a folder with a loose file and one *other* unmarked, non-lesson
  subfolder (not named Attachments/Removed); confirm **Transform to
  Lesson** still succeeds and that subfolder now appears as a ghost inside
  the new lesson's detail pane.
- Create a folder that has a real nested lesson inside it (a subfolder
  with the hidden `.lesson` marker); confirm **Transform to Lesson** on
  the *outer* folder is still rejected — this is the one case that should
  still block, since the folder is genuinely a Category.
- Select a lesson with an extra, unrecognized file sitting in its folder
  (e.g. a second video that lost the disambiguation, or a stray text
  file); confirm it appears under "Other Files In This Lesson" in the
  detail pane, dimmed, below Attachments.
- Confirm ghosts never appear anywhere when editing is off — this should
  require no special checking, since ghost rendering is entirely gated
  behind the same `isEditingModule` flag as every other editing
  affordance.

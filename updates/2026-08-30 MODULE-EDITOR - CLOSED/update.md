# MODULE-EDITOR

**Status:** CLOSED
**Opened:** 2026-08-30
**Closed:** 2026-08-30

## Goal

Let the user restructure a classroom from inside the app instead of by hand
in Finder: reorder, create, rename, and Trash categories/lessons; turn a
plain folder into a lesson; and manage a lesson's media/notes/attachments —
all without ever silently losing saved progress, completion state, or
custom order.

## Revision: editing lives in the existing view, not a separate screen

The first version of this update built a dedicated two-pane editor screen
(a raw file/folder tree on the left, a differently-styled outline and
lesson panel on the right), opened as a modal sheet over the gallery. After
seeing it, the user rejected it outright: *"the UI is terrible... must look
exactly as when you open the module - IDENTICAL. And everything must be
editable there."*

That's a real, correct call — a bespoke screen that looks nothing like the
rest of the app is bad UX regardless of what it can do. The whole thing was
rebuilt around a different premise: **editing is a mode of the exact same
sidebar and detail pane normal browsing already uses**, not a different
view. `ClassroomSidebarView` and `ClassroomBrowserView`'s detail pane are
unchanged in their non-editing form — pixel-identical to before this
update — and gain inline affordances only when `viewModel.isEditingModule`
is on:

- Module name and description become editable text fields in the sidebar's
  section header.
- Lesson and category rows get inline rename, a drag handle for reorder
  (reusing the ordering system that already existed) and reparent, and
  context-menu Rename/Transform to Lesson/Move to Trash.
- **+** rows appear to create a new direct lesson, a lesson inside a
  category, or a new category.
- The lesson detail pane's media area becomes a drop zone that replaces
  the hero media (demoting the old file to `Attachments/`); the notes area
  becomes a drop zone that inserts a Markdown link without moving
  anything; the attachments section grows a drop zone to add files and an
  **X** per attachment to remove one.

This also simplified the underlying design a lot. The original version
needed a parallel raw-filesystem-tree data model (`FileNode`,
`ModuleFileTreeScanner`) and a second view model
(`ClassroomEditorViewModel`) specifically because the bespoke screen needed
to show *un*recognized loose files/folders that the normal sidebar doesn't
display. Once editing happens inside the normal sidebar, that's no longer
needed: under the marker-file model, any folder directly under a module
that isn't yet a lesson already reads as a **Category** — so it's already
visible, and "Transform to Lesson" is just a context-menu action on a
Category row. All editing operations now live directly on
`ClassroomBrowserViewModel`, calling straight into `ClassroomEditorService`
and `MetadataStore.migratePath`. `FileNode`, `ModuleFileTreeScanner`, and
`ClassroomEditorViewModel` were deleted; `ClassroomEditorService` and
`MetadataMigrationService` (the actual file-operation and metadata-safety
logic) were unaffected by the rework and are reused as-is.

## Entry points

- Right-click a module card in the gallery → **"Open as Editor"** — opens
  the module with editing already switched on.
- An **Edit** / **Done** toggle in an already-open module's sidebar header
  (next to the back button) — lets you turn editing on or off without
  leaving the module.

## Decisions locked in during scoping

- **Dragging a file in from Finder moves it**, not copies it — consistent
  with dragging an attachment *out* to Finder, which is necessarily a move
  once a real `file://` URL is involved.
- **Deleting a whole Category or Lesson goes to the real macOS Trash**
  (`FileManager.trashItem`) — distinct from the attachment-level `Removed/`
  folder, which stays inside the lesson on purpose. Trash is "get this out
  of the classroom entirely, but recoverably"; `Removed/` is "keep it in
  the classroom but out of the way," and isn't shown to normal browsing for
  the same reason `Attachments/` isn't shown unless it's the recognized
  folder — no scanner change was needed for this, it was already true.

## Edge cases identified and designed for

- **Metadata must survive rename and move.** A Lesson's identity key is its
  relative path, which changes on rename or reparent. Without explicit
  handling this would silently orphan playback position, completion, and
  custom order — exactly the failure mode the original product spec's
  "In-App Rename Behavior" section warned about. `MetadataMigrationService`
  rewrites `lessonState`/`lessonOrder`/`categoryOrder`/`moduleOrder` keys
  and values by path prefix, cascading correctly whether a Module,
  Category, or Lesson is the thing being renamed or moved (renaming a
  Module or Category cascades into every lesson beneath it; moving a
  Lesson to a new parent drops its old ordering reference and lets it
  re-append naturally, matching how newly-discovered items already
  behave).
- **Name collisions.** Rename/move reject a destination name that already
  exists (matches the original spec's rename validation rules — no silent
  overwrite). Attachment/import moves are more forgiving: a colliding name
  gets a numeric suffix (`Handout 2.pdf`) rather than failing, since adding
  a file isn't a precise, named operation the way a rename is.
- **Empty/whitespace-only names** are rejected, same as the original spec's
  rename rules; `/` and `:` are rejected too.
- **"Transform to Lesson" on a folder that already has subfolders** is
  rejected with a clear message — transform only has well-defined behavior
  for a folder of loose files, and a folder with subfolders is likely
  already functioning as a Category with real lessons inside it.
- **Renaming the Module itself** updates `ClassroomBrowserViewModel`'s own
  `selectedModuleID` immediately, so editing doesn't lose its place
  mid-rename.
- **No visual difference when not editing.** This was the whole point of
  the rework — verified by reading through both views and confirming every
  new affordance is gated behind `viewModel.isEditingModule`, with the
  non-editing branch matching the pre-editor code exactly.
- **Dirty notes aren't lost by an unrelated edit.** Every editing action
  routes through the existing `refresh()`, which already flushes
  `saveSelectedNoteIfNeeded()` before rescanning — so replacing hero media
  or adding an attachment mid-note-edit doesn't blow away unsaved notes
  text.

## Plan

See `roadmap.md` — written for the original two-pane-screen design. Phases
A and B (metadata migration, `ClassroomEditorService`) shipped as planned
and are unaffected by the later rework. Phases C–G were superseded by the
in-place-editing approach described above.

## What shipped

- `MetadataMigrationService` + `MetadataStore.migratePath` — path-prefix
  rewrite for rename/move, cascading correctly for module/category/lesson.
- `ClassroomEditorService` — transform-to-lesson (with ambiguous
  media/notes detection and a subfolder/already-a-lesson guard), create
  category/lesson, rename, move (reparent), Trash, `importFile` (always a
  move, auto-disambiguates name collisions), attachment add/remove (remove
  → lesson-local `Removed/`, never deletes), hero-media replace (demotes
  the old file to `Attachments/`).
- `ClassroomBrowserViewModel` grew editing methods (rename/create/move/
  trash/transform for modules, categories, and lessons; hero/notes-link/
  attachment operations scoped to the selected lesson) plus
  `isEditingModule` and `pendingTransform` state — no separate view model.
- `ClassroomSidebarView` and `ClassroomBrowserView`'s detail pane gained
  inline editing affordances, gated behind `isEditingModule`, with zero
  layout change when editing is off.
- `SidebarModule` gained a `description` field so the sidebar header can
  show/edit it (mirrors what `GalleryModule` already carried).
- `TransformDisambiguationSheet` retargeted at
  `ClassroomBrowserViewModel.PendingTransform`.

## Verification

- `swift build` — clean.
- `swift run ClassroomSmokeTests` — passed, exercising the full editing
  flow through `ClassroomBrowserViewModel`: edit-mode toggle, drag-reorder
  of direct lessons and categories, create category, transform-to-lesson,
  move (reparent) with metadata migration, rename with metadata migration,
  module description update, module rename cascading metadata to nested
  lessons, and Trash — all verified with real execution against a real
  filesystem, not just compiled. Also caught and fixed a real test-fixture
  mistake along the way (a loose untransformed folder reads as a Category
  too, so it must appear in category-order assertions).
- `swift test` — compiles; this sandbox has no `xctest` runner to actually
  execute the XCTest bundle (see the note in the GALLERY-LESSON-FOLDERS
  update) — run it for real on a machine with Xcode installed.
- The UI itself (drag-and-drop feel, inline rename focus behavior, drop
  zone hit-testing) was never visually exercised in this session — there's
  no way to drive a macOS GUI from this environment. It builds and
  type-checks cleanly, and every operation it calls into is independently
  verified, but run through `docs/phase-9-checklist.md` by hand before
  treating the interactions themselves as confirmed.

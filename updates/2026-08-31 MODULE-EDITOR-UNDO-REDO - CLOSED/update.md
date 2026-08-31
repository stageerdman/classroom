# MODULE-EDITOR-UNDO-REDO

**Status:** CLOSED
**Opened:** 2026-08-31
**Closed:** 2026-08-31

## Goal

Second follow-up from the same CORE 100 testing session as
`2026-08-31 MODULE-EDITOR-GHOST-BROWSING`. Two more problems surfaced:

1. **A real, more serious bug**: right-clicking a ghost folder nested
   inside a category and choosing "Transform to Lesson" transformed the
   *category* instead — which also explains the earlier-reported false
   "this folder contains subfolders" message (it was correctly describing
   the category, which legitimately has multiple lesson subfolders, not
   the ghost folder the user actually clicked).
2. **Feature request**: undo/redo for editing actions, including the
   standard Cmd-Z / Cmd-Shift-Z shortcuts.

## Root cause of the context-menu bug

`.contextMenu` (and `.dropDestination`) were attached to the whole
`DisclosureGroup` for a category — `label: { categoryLabel(category) }`
followed by `.contextMenu { categoryContextMenu(category) }` *outside* the
closure, which applies the modifier to the entire group including its
expanded content. A `DisclosureGroup`'s content is part of the same view
subtree as the group itself, so a right-click anywhere inside its expanded
children (a nested ghost row, a lesson row) was being captured by the
category's own context menu instead of reaching the more specific one
attached to the actual row underneath the cursor. The exact same bug
pattern existed in `GhostEntryRow` for nested ghost folders (a `Transform
to Lesson` on a doubly-nested ghost folder would have hit the *outer*
ghost folder's menu instead).

**Fix**: interaction modifiers (`contextMenu`, `draggable`,
`dropDestination`) now live on the `label` closure content specifically,
not on the `DisclosureGroup` as a whole, in both `ClassroomSidebarView`
(category rows) and `GhostEntryRow` (nested ghost folder rows).

## What shipped

- Context-menu/drag/drop scoping fix described above.
- `ClassroomBrowserViewModel.undoManager` (`Foundation.UndoManager`,
  `groupsByEvent = false` so grouping is always explicit rather than tied
  to run-loop timing) wired to the system Edit menu's Undo/Redo items —
  `ClassroomApp.swift` replaces the default (inert, since this app
  doesn't publish `\.undoManager` into the SwiftUI environment —
  `EnvironmentValues.undoManager` turned out to be effectively read-only
  in the current SDK, so injecting a custom manager that way didn't
  compile) `CommandGroup(.undoRedo)` with `Undo`/`Redo` items bound to
  Cmd-Z / Cmd-Shift-Z, broadcasting through the same NotificationCenter
  pattern already used for Open/Refresh; `ClassroomBrowserView` listens
  and calls `viewModel.undoManager.undo()` / `.redo()`.
- Undo/redo coverage for the structural editing operations: rename
  (module/category/lesson), create (category/lesson — undone via Trash
  rather than a hard delete, so anything dropped into it before the undo
  isn't silently lost), move/reparent (lesson and ghost), transform to
  lesson (undo moves archived files back out of `Attachments/` and
  removes the marker — and the `Attachments/` folder itself, but only if
  the transform is what created it), and Move to Trash (undo restores
  from the real Trash to the exact original path).
- Deliberately **not** covered by undo in this round: reordering, notes
  text, playback/completion state, module description, and lesson-level
  hero-media/attachment/notes-link edits. Lower risk, and reordering/notes
  already have their own recovery paths (drag back, or the note simply
  wasn't saved yet). Revisit if this turns out to matter in practice.
- `ClassroomEditorService` gained the plumbing undo needed: `trash(_:)`
  now returns the resulting Trash URL (macOS can rename on collision, so
  the caller needs to know exactly where it landed to restore it later);
  a new `restore(_:to:)` moves an item back from the Trash to an exact
  destination; `transformToLesson` now returns a `TransformResult`
  (archived file names + whether it created `Attachments/`) and a new
  `undoTransformToLesson(_:result:)` reverses it precisely.

## Design note: two different undo patterns

Rename/create/move are deterministic — the same inputs always produce the
same destination path — so their undo/redo just ping-pongs between two
fixed closures via a generic `registerUndoRedo(actionName:undoAction:
redoAction:)` helper. Trash isn't deterministic: `FileManager.trashItem`
can rename an item inside the Trash to dodge a collision with something
already there, so each trash produces a *different* URL to restore from.
That URL has to thread through every subsequent undo/redo step rather
than being fixed at registration time, so trash/restore uses its own
mutually-recursive pair (`registerRestoreUndo` / `performRestore` /
`registerTrashUndo` / `performTrash`) that re-captures the fresh trashed
URL on every cycle instead of reusing the generic helper.

## Verification

- `swift build` — clean.
- `swift run ClassroomSmokeTests` — passed, extended with an end-to-end
  undo/redo pass exercising rename, create, move/reparent, trash/restore,
  and transform, each checked with undo *and* redo (not just undo) against
  a real filesystem and the real `UndoManager`.
- `swift test` — compiles (including new `ClassroomEditorServiceTests`
  coverage for `trash`/`restore` and `undoTransformToLesson`, plus a case
  confirming a pre-existing `Attachments/` folder survives a transform
  undo); no `xctest` runner in this sandbox, same standing note as prior
  updates.
- The context-menu fix itself — the actual reported bug — was not
  re-exercised through a live right-click in this session (no way to
  drive a macOS GUI here). The fix is a structural one (moving modifiers
  off the DisclosureGroup onto the label) that's straightforward to
  verify by inspection, but confirm by hand: right-click a ghost folder
  nested inside a category and make sure "Transform to Lesson" acts on
  that folder, not the category.

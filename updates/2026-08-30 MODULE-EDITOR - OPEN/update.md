# MODULE-EDITOR

**Status:** OPEN
**Opened:** 2026-08-30

## Goal

Add a structural editor for a module's contents, reachable by right-clicking
a module card in the gallery and choosing **"Open as Editor."** Today the
only way to restructure a classroom is by hand in Finder; this update adds
an in-app editor that can see and rearrange everything on disk inside one
module — including the loose, unclassified files/folders that the normal
scanner ignores — without ever silently losing the user's saved progress,
completion state, or custom order.

The editor is a separate mode from normal browsing (`ClassroomBrowserView`
stays exactly as shipped). It opens as a modal sheet over the gallery, scoped
to the one module that was right-clicked.

### What it does

1. **Two-pane layout.** Left: a raw file/folder tree of the module's actual
   filesystem contents (including folders the normal scanner would treat as
   opaque, like `Attachments/` and the new `Removed/` folder — see below).
   Right: the structured Category/Lesson outline, reorderable by drag (reuses
   the existing ordering system), with **+** buttons to create a new Category
   or Lesson.

2. **Transform to Lesson.** Right-click any plain folder in the raw tree →
   "Transform to Lesson." This adds the hidden `.lesson` marker file. If the
   folder has more than one playable file, the user is prompted to pick the
   main one; same for `.md` files. Every other loose file at that folder's
   top level moves into an `Attachments/` folder (created if it doesn't
   exist). Pre-existing subfolders are left untouched. Disabled if the
   folder already contains subfolders (ambiguous — could already be a
   Category), or is already a lesson.

3. **Create / drag / reparent.** New Categories and Lessons can be created
   via **+**, immediately rename-in-place (like Finder's "untitled folder"),
   and dragged anywhere in the module — including across categories, since
   this is a real move on disk, not just a metadata reorder.

4. **Three lesson drop zones**, once a lesson is open in the editor's detail
   panel:
   - **Hero (media)** — drop a playable file here to replace the lesson's
     media. The old media (if any) moves into `Attachments/` rather than
     being deleted.
   - **Notes text** — drop any file here to insert a Markdown link to it
     at its current location. Nothing is moved or copied — this is the one
     lightweight zone that just references a file in place.
   - **Attachments** — drop a file here to add it as an attachment (moves
     it into `Attachments/`, creating the folder if needed).

   All three accept drags from Finder or from the editor's own raw-tree
   panel.

5. **Removing an attachment** (the **X** next to it) doesn't delete it — it
   moves the file into a `Removed/` folder inside that same lesson. This
   folder is visible in the editor's raw tree (so nothing is silently lost)
   but invisible to normal browsing, exactly like `Attachments/` already is
   unless it's the recognized one.

6. **Drag out to Finder.** Dragging an attachment (from the lesson panel or
   the raw tree) out to Finder moves the real file there — this relies on
   standard macOS drag behavior for a genuine `file://` URL, not a custom
   "delete after drop" step.

7. **Rename / Trash / edit description.** Any Module, Category, or Lesson
   can be renamed in place. Module and Category get a Trash action (real
   macOS Trash, recoverable). The module's `description.md` (used on its
   gallery card) is editable directly in the editor's header, autosaved like
   lesson notes.

## Decisions locked in during scoping

- **Dragging a file in from Finder moves it**, not copies it — consistent
  across both directions (drag out already had to be a move per how Finder
  drag-and-drop works with a real file URL; drag in matches it rather than
  behaving asymmetrically).
- **Deleting a whole Lesson or Category goes to the real macOS Trash**
  (`FileManager.trashItem`) — distinct from the attachment-level `Removed/`
  folder, which stays inside the classroom on purpose so it shows up in the
  editor's raw tree. Trash is for "get this out of the classroom entirely,
  but recoverably"; `Removed/` is for "keep this in the classroom but out of
  the way."
- **The editor is scoped to one module**, matching its entry point (right-
  click that module's card). It doesn't show sibling modules.

## Edge cases identified and designed for

- **Metadata must survive rename and move.** A Lesson's identity key is its
  relative path, which changes on rename or reparent. Without explicit
  handling this would silently orphan playback position, completion, and
  custom order — exactly the failure mode the original spec's "In-App Rename
  Behavior" section warned about. This update adds a dedicated
  `MetadataMigrationService` that rewrites `lessonState`/`lessonOrder`/
  `categoryOrder`/`moduleOrder` keys and values by path prefix, cascading
  correctly whether a Module, Category, or Lesson is the thing being renamed
  or moved (renaming a Module or Category cascades into every lesson beneath
  it; moving a Lesson to a new parent drops its old ordering reference and
  lets it re-append naturally, matching how newly-discovered items already
  behave).
- **Name collisions.** Rename/move reject a destination name that already
  exists (matches the original spec's rename validation rules — no silent
  overwrite). Attachment/import moves are more forgiving: a colliding name
  gets a numeric suffix (`Handout 2.pdf`) rather than failing, since adding
  a file isn't a precise, named operation the way a rename is.
- **Empty/whitespace-only names** are rejected, same as the original spec's
  rename rules; `/` and `:` are rejected too.
- **"Transform to Lesson" on a folder that already has subfolders** is
  disabled in the UI — transform only has well-defined behavior for a folder
  of loose files, and a folder with subfolders might already be functioning
  as a Category.
- **Renaming the Module itself** (not just its contents) is supported from
  the editor header, since that's a natural thing to want once you're
  editing a module. It updates the editor's own "which module is open"
  tracking so it doesn't lose its place mid-rename.
- **The `Removed/` folder is invisible to normal browsing "for free"** — the
  scanner already only recognizes a folder literally named `Attachments` as
  attachments; anything else sitting alongside a lesson's files (like
  `Removed/`) was already ignored before this update. No scanner change
  needed to hide it from end users; only the editor's raw tree needs to
  reveal it deliberately.
- **No live-playback conflict.** The editor is entered from the gallery
  (right-click a module card), not from an already-open module/player view,
  so there's no scenario where the editor and the normal player are open on
  the same module at the same time.
- **Refresh.** The editor gets its own refresh action (reusing the existing
  rescan pipeline) so changes made by dragging a file out to Finder — which
  the app can't observe happening — are picked up on demand, consistent with
  the rest of the app's existing refresh-on-demand posture (there's no
  filesystem watcher anywhere yet).

## Plan

See `roadmap.md` for the phase breakdown.

## Verification

- `swift build`
- `swift run ClassroomSmokeTests`
- `swift test` (compiles; this sandbox can't execute the XCTest bundle — see
  note in the GALLERY-LESSON-FOLDERS update)
- Manual checklist: `docs/phase-9-checklist.md`

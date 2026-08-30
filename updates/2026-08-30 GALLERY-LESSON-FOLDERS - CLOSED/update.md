# GALLERY-LESSON-FOLDERS

**Status:** CLOSED
**Opened:** 2026-08-30
**Closed:** 2026-08-30

## Goal

Two related structural changes, requested together because the second one
motivates the first:

1. **Navigation split.** Opening a classroom no longer drops the user
   straight into the sidebar-plus-player layout. It shows a Notion-gallery
   style grid of Module cards (bold name, description, progress) with no
   sidebar and no progress chrome. The sidebar, categories, lesson list, and
   player only appear after the user opens a specific Module. Reopening a
   different classroom happens through **File → Open Recent**, not a Recents
   list embedded in the main window.

2. **Lesson folders.** A Lesson stops being a single video file with a
   sibling `.md`. A Lesson becomes a **folder**, marked as a lesson by a
   hidden marker file so it can be told apart from a Category folder at a
   glance without inspecting contents. Inside a Lesson folder:
   - at most one playable media file (video or audio — same "any format
     like that" breadth as today's video-only rule, just widened), rendered
     at the top exactly like today's player;
   - at most one `.md` file, the lesson body/notes;
   - an optional `Attachments/` folder — if present and non-empty, its
     files are listed as attachments at the bottom of the lesson and can be
     opened individually. If absent or empty, no Attachments section is
     shown.

   Modules keep their current shape (a Module folder contains Category
   folders and/or lessons directly), but "lesson" is now determined by the
   marker file rather than by "this folder holds a video." A Module folder
   may also contain an optional `description.md` — its contents become the
   description shown on that module's gallery card; no file, no description.

## Why

The current layout (sidebar + categories + lessons + progress, all visible
the moment a classroom opens) doesn't scale visually once a classroom has
more than a handful of modules — everything is flattened into one tree. A
gallery of modules gives each module a clear entry point and visual identity
(name, description, progress) before committing to its contents, which is
also just a more familiar pattern (Notion-style galleries) for this kind of
content.

The lesson-folder change is what makes a real per-lesson description and
attachments possible without overloading the `.md` notes file or inventing a
second metadata channel: the filesystem structure carries this information
the same way it already carries module/category/lesson names, keeping the
app local-first and folder-driven per the product spec's core principle.

## Decisions locked in during scoping

Asked the user directly on these three points before planning, since they
change the shape of the scanner and view models:

- **Direct lessons stay legal.** A Lesson folder can sit directly under a
  Module (no Category required), same as today's direct-lesson videos.
- **Lesson marker is a hidden dotfile**, analogous to the existing
  `.local-classroom/` metadata convention — e.g. `.lesson` — placed inside a
  folder to mark it as a Lesson rather than a Category. This is what lets a
  Lesson folder and a Category folder coexist at the same depth without
  ambiguity.
- **Module description** comes from an optional `description.md` file
  inside the Module folder. No in-app editable metadata field for this.
- **This is a breaking format change.** Classrooms using the old flat
  `Lesson Name.mp4` + `Lesson Name.md` pairing are not auto-migrated. The
  scanner stops recognizing that shape; existing classrooms need manual
  restructuring into the new Lesson-folder format. No compatibility shim, no
  assisted migration tool, per explicit user direction.

## Consequence worth flagging

Because a Lesson's identity key changes from "video file relative path" to
"lesson folder relative path," `classroom.json` metadata written under the
old scheme (playback position, completion, custom order) will not match up
against restructured classrooms. Existing classrooms lose their saved
progress/order once restructured into folders — same class of behavior the
spec already accepts for out-of-app renames (metadata becomes orphaned and
ages out), just triggered here on purpose by the format migration rather than
a Finder rename. This is expected, not a bug, and should be called out
plainly if/when we write user-facing notes about this update.

## Plan

See `roadmap.md` for the phase-by-phase breakdown that was followed.

## What shipped

- **Phase A** — `ClassroomScanner`/`ClassroomModels` rewritten: a folder is
  a Lesson iff it contains the hidden `.lesson` marker file
  (`ClassroomScanner.lessonMarkerFileName`); media extensions widened to
  video + audio; `Attachments/` folder contents exposed as
  `Lesson.attachmentURLs`; `ClassroomModule.description` read from an
  optional `description.md`. New `ClassroomWarning` kinds
  (`.ambiguousLessonMedia`, `.ambiguousLessonNotes`) replace the removed
  `.duplicateVideoBasename` case, which no longer applies once lessons are
  folders.
- **Phase B** — `NotesService` falls back to a canonical `Notes.md` inside
  the lesson folder when no `.md` exists yet; `ClassroomBrowserViewModel`
  and view code updated for optional `mediaURL`/`notesURL`.
- **Phase C** — new navigation state on `ClassroomBrowserViewModel`
  (`selectedModuleID`, `openModule`/`closeModule`, `galleryModules`); new
  `ClassroomGalleryView` (Notion-style module card grid: name, description,
  progress); `ClassroomSidebarView` rescoped to a single module;
  `ClassroomBrowserView` rewritten as a router between gallery / module
  detail / empty state.
- **Phase D** — Recents removed from the sidebar; File → Open Recent added
  in `LocalClassroomApp.swift`, backed by a new `RecentClassroomsMenuModel`
  that listens for the new `.recentClassroomsDidChange` notification posted
  by the view model.
- **Phase E** — Attachments section in the lesson detail view, rendered
  only when `lesson.attachmentURLs` is non-empty; each attachment opens via
  `NSWorkspace`.
- **Phase F** — `Tests/LocalClassroomSmokeTests/main.swift` rewritten
  end-to-end for lesson-folder fixtures (marker detection, ambiguous media,
  attachments, module descriptions, gallery/module navigation, ordering
  keyed by folder name); `Tests/LocalClassroomCoreTests/SmokeTests.swift`
  fixed (it referenced undefined `ModelNamespace`/etc. — a pre-existing,
  unrelated break — and was replaced with real `ClassroomScanner`
  coverage); `docs/phase-8-checklist.md` added; `README.md` structure
  section rewritten for the new format; launcher app rebuilt via
  `scripts/create-launcher-app.sh`.

## Verification

- `swift build` — clean.
- `swift run LocalClassroomSmokeTests` — passed (only reliable way to
  execute test assertions in this sandbox; see note below).
- `swift test` — compiles cleanly against `@testable import
  LocalClassroomCore`, but this sandboxed environment has no `xctest`
  runner (no Xcode Developer directory), so the XCTest bundle cannot
  actually execute here. Run it for real on a machine with Xcode installed.
- Manual verification checklist: `docs/phase-8-checklist.md`. Not run
  live in this session (no way to drive a macOS GUI app from this
  environment) — run it by hand after relaunching `Local Classroom.app`.

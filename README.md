<p align="center">
  <img src="Sources/ClassroomApp/Resources/classroom-icon.png" alt="Classroom logo" width="96" height="96">
</p>

# Classroom

A local-first macOS app that turns any folder into a browsable classroom —
no upload, no duplication, no server. The folder structure is the source of
truth: folder names become classrooms, modules, categories, and lessons.

Opening a classroom shows a gallery of module cards (name, description,
progress); opening a module reveals the same sidebar of categories and
lessons it always has. Right-clicking a module card (or the **Edit** button
in an open module's sidebar) turns on editing directly in that same view —
no separate editor screen. While editing you can rename the module,
categories, and lessons in place; create new ones; drag a lesson to
reorder or reparent it across categories; transform a plain folder into a
lesson; Trash a category or lesson; and drop files onto a selected lesson's
media, notes, or attachments. See `classroom_spec.md` for the
original product and engineering spec,
`updates/2026-08-30 GALLERY-LESSON-FOLDERS - CLOSED/update.md` for the
gallery/lesson-folder update,
`updates/2026-08-30 MODULE-EDITOR - CLOSED/update.md` for the editor,
`updates/2026-09-02 NOTES-PAGE-SPLIT - CLOSED/update.md` for the Page/Notes
split and timenotes, and
`updates/2026-09-02 BLOCKNOTE-EDITOR - OPEN/update.md` for the BlockNote
rich text editor.

## Structure

```text
Classroom Root/                  Depth 1: Classroom
├── Module A/                     Depth 2: Module
│   ├── description.md            Optional — module card description
│   ├── Lesson 1/                  Depth 3: Direct lesson folder
│   │   ├── .lesson                 Hidden marker — this folder is a lesson
│   │   ├── Lesson 1.mp4            At most one playable media file
│   │   ├── page.md                 Authored lesson content (edit-mode only)
│   │   ├── note.md                 The viewer's own notes (always editable)
│   │   └── Attachments/            Optional — files attached to the lesson
│   │       └── Handout.pdf
│   └── Category A/                Depth 3: Category (no marker file)
│       └── Lesson 2/               Depth 4: Lesson folder
│           ├── .lesson
│           └── Lesson 2.mov
└── Module B/
```

A folder is a **Lesson** if it directly contains a hidden `.lesson` marker
file — that's what lets a Lesson folder and a Category folder coexist at
the same depth. A Lesson folder holds at most one playable media file
(`.mp4`, `.mov`, `.m4v`, `.mp3`, `.m4a`, `.wav`, `.flv`), a `page.md`, a
`note.md`, and an optional `Attachments/` folder; attachments only show up
in the UI when that folder is present and non-empty. Removing an
attachment from the editor moves it into a `Removed/` folder inside that
lesson rather than deleting it — visible in the editor's raw file tree,
invisible to normal browsing, same as `Attachments/` is until it's the
recognized folder.

`.flv` is recognized so a lesson built around one isn't silently treated
as having no media, but macOS's AVFoundation has no FLV demuxer — playing
one shows a clear "convert it to MP4 or MOV" message rather than a silent
dead player. Any other file or folder sitting in a lesson's folder besides
its chosen media, `page.md`/`note.md`, and `Attachments/`/`Removed/` shows
up while editing as a dimmed "ghost" entry; ghost folders (anywhere —
module, category, or inside a lesson) open to browse their contents
recursively, and files/folders can be dragged between them to reorganize.
A lesson from before the Page/Notes split (a single arbitrary `.md` file)
has that file renamed to `page.md` automatically the first time it's
scanned.

### Page and Notes

A lesson's content area has a top selector — **Page**, **Notes** — above
the video/audio player. Selecting one shows it full-width; selecting both
splits the pane in two. **Page** (`page.md`) is the lesson's authored
content: read-only unless the containing Module is in edit mode. **Notes**
(`note.md`) is the viewer's own running notes: always editable, in or out
of edit mode.

Both are edited with [BlockNote](https://github.com/TypeCellOS/BlockNote),
a block-based rich text editor running in an embedded `WKWebView`
(`BlockNoteEditorView.swift`) — not a native AppKit text view. `page.md`/
`note.md` on disk stay ordinary Markdown files; BlockNote converts to/from
Markdown on load/save (`blocksToMarkdownLossy`/`tryParseMarkdownToBlocks`)
so the rest of the app never knows the editing surface is a web view.
See `updates/2026-09-02 BLOCKNOTE-EDITOR - OPEN/update.md` for how the
web app is built and bridged to Swift, and
`webviews/blocknote-editor/` for its source.

Notes support **timenotes** — inline links back to a moment in the
lesson's video/audio, rendered as a clickable timestamp
(`[HH:MM:SS.mmm](classroom-timenote:<seconds>) your note text` — plain
CommonMark, no custom syntax). Create one by clicking the comment-bubble
button in the video transport bar (inserts a timenote at the current
position and focuses Notes), or by typing `/timenote` inside Notes,
Notion-style. `HH:MM:SS.mmm` (period-delimited milliseconds) is
deliberately the same clock a future transcript feature would use, so
notes and transcript cues can line up without a conversion step.

Any other Markdown file opened from a ghost/attachment while editing
still opens in the app's original lightweight native editor
(`MarkdownNotesView.swift`) — Obsidian-style live styling, hidden syntax
markers, Cmd-B/I/U — since those are one-off arbitrary files, not the
main Page/Notes editing surface.

This is a breaking format change from the original flat
`Lesson Name.mp4` + `Lesson Name.md` layout — classrooms in the old format
need to be manually restructured into lesson folders; there is no
automatic migration.

## Building

```sh
swift build
swift test
swift run ClassroomSmokeTests
swift run Classroom
```

To build the standalone `.app` launcher:

```sh
scripts/create-launcher-app.sh
```

## Project layout

- `Sources/ClassroomCore` — non-UI, testable core (models, services,
  view models).
- `Sources/ClassroomApp` — SwiftUI app and views.
- `Tests/` — unit and smoke tests.
- `docs/` — phase-by-phase scope and verification checklists.
- `updates/` — dated update folders tracking what shipped and why (see
  `CLAUDE.md` for the workflow).
- `webviews/` — standalone Node/npm web projects whose static build
  output gets bundled as app resources (currently just
  `blocknote-editor/`, the Page/Notes editor — see
  `updates/2026-09-02 BLOCKNOTE-EDITOR - OPEN/update.md`). `swift build`
  never needs Node; only editing a `webviews/*` project does, via its
  own `scripts/build-*.sh` to refresh the bundled copy under
  `Sources/ClassroomApp/Resources/`.

## Working on this repo

See `CLAUDE.md` for the working principles and update-tracking workflow used
in this project.

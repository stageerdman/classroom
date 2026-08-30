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
media, notes, or attachments. See `local_classroom_codex_spec.md` for the
original product and engineering spec,
`updates/2026-08-30 GALLERY-LESSON-FOLDERS - CLOSED/update.md` for the
gallery/lesson-folder update, and
`updates/2026-08-30 MODULE-EDITOR - CLOSED/update.md` for the editor.

## Structure

```text
Classroom Root/                  Depth 1: Classroom
├── Module A/                     Depth 2: Module
│   ├── description.md            Optional — module card description
│   ├── Lesson 1/                  Depth 3: Direct lesson folder
│   │   ├── .lesson                 Hidden marker — this folder is a lesson
│   │   ├── Lesson 1.mp4            At most one playable media file
│   │   ├── Lesson 1.md             At most one Markdown notes file
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
(`.mp4`, `.mov`, `.m4v`, `.mp3`, `.m4a`, `.wav`), at most one `.md` notes
file, and an optional `Attachments/` folder; attachments only show up in
the UI when that folder is present and non-empty. Removing an attachment
from the editor moves it into a `Removed/` folder inside that lesson
rather than deleting it — visible in the editor's raw file tree, invisible
to normal browsing, same as `Attachments/` is until it's the recognized
folder.

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

## Working on this repo

See `CLAUDE.md` for the working principles and update-tracking workflow used
in this project.

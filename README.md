# Local Classroom

A local-first macOS app that turns any folder of video files into a
browsable classroom — no upload, no duplication, no server. The folder
structure is the source of truth: folder names become classrooms, modules,
and categories, and video filenames become lesson names.

See `local_classroom_codex_spec.md` for the full product and engineering
spec.

## Structure

```text
Classroom Root/          Depth 1: Classroom
├── Module A/             Depth 2: Module
│   ├── Lesson 1.mp4       Depth 3: Direct lesson
│   ├── Category A/        Depth 3: Category
│   │   └── Lesson 2.mp4    Depth 4: Lesson
│   └── Lesson 4.m4v
└── Module B/
```

Supported video formats: `.mp4`, `.mov`, `.m4v`.

## Building

```sh
swift build
swift test
swift run LocalClassroomSmokeTests
swift run LocalClassroom
```

To build the standalone `.app` launcher:

```sh
scripts/create-launcher-app.sh
```

## Project layout

- `Sources/LocalClassroomCore` — non-UI, testable core (models, services,
  view models).
- `Sources/LocalClassroomApp` — SwiftUI app and views.
- `Tests/` — unit and smoke tests.
- `docs/` — phase-by-phase scope and verification checklists.
- `updates/` — dated update folders tracking what shipped and why (see
  `CLAUDE.md` for the workflow).

## Working on this repo

See `CLAUDE.md` for the working principles and update-tracking workflow used
in this project.

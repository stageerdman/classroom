# INIT

**Status:** CLOSED
**Opened:** 2026-07-11
**Closed:** 2026-07-11

## Summary

Baseline build of Classroom, a local-first macOS app that turns any
selected folder of video files into a browsable classroom. No upload, no
duplication, no server — the folder structure is the source of truth. Built
incrementally in phases, each with automated tests and a manual verification
pass before moving on.

## What shipped

- **Phase 0** — SwiftUI app skeleton, `ClassroomCore` module for
  testable non-UI code, smoke test target.
- **Phase 1** — Folder-to-classroom scanning (classroom → module → category →
  lesson, 4 levels deep) driven purely by filesystem structure.
- **Phase 2** — Classroom browsing UI: modules, categories, and lessons
  rendered from the scanned folder tree.
- **Phase 3** — Lesson playback and lesson notes (matching `.md` files).
- **Phase 4** — Completion tracking and playback position persistence.
- **Phase 5** — Sidebar navigation and completed-lesson visibility
  (`60701c4`).
- **Phase 6** — Standard classroom layout cleanup (`8075853`).
- **Phase 7** — Custom classroom ordering: stored order for modules,
  categories, direct lessons, and category lessons; merges saved order with
  newly discovered files (appended via natural sort); per-scope reset; drag
  and context-menu reorder actions in the sidebar (`eec7891`).
- Lesson view controls simplified (`d6b27ae`).
- `.app` launcher packaging via `scripts/create-launcher-app.sh`.

Full phase-by-phase scope and manual verification checklists live in
`docs/phase-0-checklist.md` through `docs/phase-7-checklist.md`.

## Verification

- `swift test`
- `swift run ClassroomSmokeTests`
- `swift build`
- Manual: open `Classroom.app`, point it at a folder with the
  classroom/module/category/lesson structure, confirm scan, playback,
  completion state, and custom ordering all behave as specced.

## Why CLOSED

This update covers the full v1 baseline described in
`local_classroom_codex_spec.md` (local-first, folder-driven, non-destructive,
simple identity model). All phase checklists are complete and verified. Next
work starts as a new update folder under `updates/`.

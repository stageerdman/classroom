# Phase 6 Checklist

> Superseded by `updates/2026-09-02 NOTES-PAGE-SPLIT - CLOSED/update.md`
> (the single "first `.md` file found" lookup below was replaced by fixed
> `page.md`/`note.md` filenames, with a two-section Page/Notes UI, split
> view, and timestamped notes) and then
> `updates/2026-09-02 BLOCKNOTE-EDITOR - OPEN/update.md` (the editing
> widget itself moved from a native `NSTextView` to an embedded BlockNote
> WebView). This checklist is kept as a historical record of Phase 6's
> original scope.

## Scope

- Matching `.md` note lookup
- Existing Markdown note loading
- Empty editor for missing notes
- Markdown file creation on save
- 800 ms debounced autosave
- Save before lesson changes
- Save errors surfaced in the UI

## Automated Verification

- `swift test`
- `swift run ClassroomSmokeTests`
- `swift build`

## Manual Verification

- Run `swift run Classroom`.
- Open a classroom.
- Write notes for a lesson and inspect the matching `.md` file in Finder.
- Switch lessons and verify notes were saved.
- Edit a note externally, refresh or reselect the lesson, and verify updated content.
- Test save failure with a read-only folder.

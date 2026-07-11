# Phase 6 Checklist

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
- `swift run LocalClassroomSmokeTests`
- `swift build`

## Manual Verification

- Run `swift run LocalClassroom`.
- Open a classroom.
- Write notes for a lesson and inspect the matching `.md` file in Finder.
- Switch lessons and verify notes were saved.
- Edit a note externally, refresh or reselect the lesson, and verify updated content.
- Test save failure with a read-only folder.

# Phase 1 Checklist

## Scope

- In-memory classroom, module, category, lesson, and warning models
- Pure `ClassroomScanner` service
- Natural sorting helper
- Temporary developer parser view on the home screen
- Smoke coverage using temporary fixture folders

## Automated Verification

- `swift test`
- `swift run LocalClassroomSmokeTests`
- `swift build`

## Manual Verification

- Run `swift run LocalClassroom`.
- Enter a classroom folder path in the developer parser.
- Confirm parsed modules, categories, lessons, and warnings match Finder.

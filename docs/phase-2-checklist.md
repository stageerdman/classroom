# Phase 2 Checklist

## Scope

- Folder picker using `NSOpenPanel`
- Persistent security-scoped folder bookmark storage
- Recent classroom list with add, remove, and de-duplication
- Classroom hierarchy sidebar
- Refresh command
- Recoverable missing-folder error state

## Automated Verification

- `swift test`
- `swift run ClassroomSmokeTests`
- `swift build`

## Manual Verification

- Run `swift run Classroom`.
- Open a classroom folder with the toolbar folder button.
- Quit and reopen the app, then reopen the folder from Recent.
- Select modules, categories, and lessons in the sidebar.
- Add a video in Finder and press Refresh.

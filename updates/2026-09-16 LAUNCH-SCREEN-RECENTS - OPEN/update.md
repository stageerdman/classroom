# Launch Screen Recents

## Goal

Surface recent classrooms on the app's initial/empty-state screen (currently
just a wordmark + "No Classroom Open" + a single "Open Classroom..." button),
so returning to a course you already opened doesn't require going through the
`File > Open Recent` menu.

## Why

`RecentClassroomStore`/`ClassroomBrowserViewModel.recentClassrooms` have
existed since `2026-07-11 INIT`, fully wired (add/remove/list, security-scoped
resolution via `openRecent`), but the only UI for them is the menu bar. For a
single teacher who returns to the same 1-6 classroom folders across sessions,
the launch screen — not a menu — is where "pick up where I left off" belongs.

Design direction came from a dedicated design pass (see below) before writing
any code: the real job of this screen is a fast on-ramp back into a known
course, not a file browser. Once recents exist, they become the primary UI;
"Open a different folder" is demoted to secondary. No new persisted data
(no thumbnails, no stored last-opened date) — list order already encodes
recency, and existence is checked live at render time rather than cached.

## What shipped

- `RecentClassroomsEmptyStateView.swift` (new,
  `Sources/ClassroomApp/Views/`): the recents-present empty state. Small
  wordmark, "Recent Classrooms" list (name + full path per row, live
  `FileManager.fileExists` check to dim/flag folders that no longer resolve),
  hover-reveals a remove (`xmark.circle`) button, right-click "Remove from
  Recents" as a redundant discoverable path, and a secondary
  "Open a Different Folder..." link below the list.
- `ClassroomBrowserView.emptyState` now branches: zero recents keeps the
  original first-run layout unchanged; one or more recents renders the new
  view instead.
- `viewModel.errorMessage` (already set by `openResolvedURL` when a recent's
  folder fails to resolve) is now surfaced on the empty state itself — it
  previously only rendered inside `ClassroomSidebarView`, which never mounts
  while `classroom == nil`, so a broken recent failed silently before this.

## Verification

- `swift build`, `swift test`, `swift run ClassroomSmokeTests`.
- Manual (by the user):
  - Fresh state / all recents removed: unchanged first-run screen, one
    "Open Classroom..." button.
  - With 1+ recents: list appears, clicking a row opens that classroom.
  - Hover a row: remove button appears; removing it drops it from the list
    without touching the folder on disk.
  - Right-click a row: "Remove from Recents" works too.
  - Rename/move/delete a recent's folder on disk, relaunch: that row shows
    dimmed with a warning glyph; clicking it surfaces an inline error instead
    of silently doing nothing.
  - "Open a Different Folder..." still opens the standard folder picker.

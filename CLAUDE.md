# Working in this repo

Local Classroom is a local-first macOS SwiftUI app (see
`local_classroom_codex_spec.md` for the product spec). This file defines how
we work in this codebase — read it before making changes.

## Main principles

1. **Maximum modularization.** Keep files, types, and functions small and
   single-purpose. Split `LocalClassroomCore` by concern (`Models/`,
   `Services/`, `ViewModels/`) and keep views broken into small, composable
   pieces. The goal is that any change only requires reading a small,
   relevant slice of the codebase — not the whole project. If a file is
   getting hard to hold in your head, split it.

2. **Always git commit and publish.** Work isn't done until it's committed
   and pushed. Commit at meaningful checkpoints (not one giant commit at the
   end), write commit messages that explain *why*, and push to `origin`
   after committing unless the user says otherwise.

3. **Always update proper documentation.** Code changes ship with the docs
   that describe them:
   - Phase/feature checklists in `docs/` when scope or verification steps
     change.
   - The active update's `update.md` (and `roadmap.md` if present) in
     `updates/`.
   - `README.md` if the change affects how the app is built, run, or used.
   Undocumented changes are treated as incomplete.

4. **Always build.** Before considering a change finished, build it
   (`swift build`, `swift test`, `swift run LocalClassroomSmokeTests`) and
   run the manual verification steps for the affected area. Then make sure
   the user is actually running the latest build — rebuild
   `Local Classroom.app` via `scripts/create-launcher-app.sh` (or the current
   equivalent) so the launcher isn't stale, and tell the user to relaunch it.
   Never report a task complete on the strength of a diff alone.

## How we track updates

Work is organized into **updates**, tracked under `updates/`. This is the
single source of truth for what shipped, when, and why — use it instead of
scattering status in chat or commit messages alone.

- Each update is a folder named `YYYY-MM-DD SHORT-NAME - STATUS`, e.g.
  `2026-07-11 INIT - CLOSED`.
  - `YYYY-MM-DD` is the date the update was opened.
  - `SHORT-NAME` is a terse slug for what the update is about.
  - `STATUS` is either `OPEN` or `CLOSED`.
- Every update folder contains:
  - `update.md` — required. What this update is, what shipped or is
    shipping, why, and how it's verified.
  - `roadmap.md` — optional. Forward-looking plan/backlog for the update,
    when there's enough scope to warrant tracking it separately from
    `update.md`.
  - Anything else relevant (notes, design docs) as needed.
- **Starting an update:** create a new folder with status `OPEN`, and write
  `update.md` describing the goal before diving into code.
- **Working an update:** keep `update.md` (and `roadmap.md`) current as
  scope becomes clearer or shifts — this is a living document, not a
  postmortem written at the end.
- **Closing an update:** when the work is done and verified, rename the
  folder's status suffix from `OPEN` to `CLOSED` and do a final pass on
  `update.md` summarizing what actually shipped. Commit the close.
- Only one update should normally be `OPEN` at a time. Ask before opening a
  second one concurrently.

## Verification

- `swift build`
- `swift test`
- `swift run LocalClassroomSmokeTests`
- Relevant manual verification checklist from `docs/` or the active update.

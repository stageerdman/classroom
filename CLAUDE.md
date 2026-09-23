# Working in this repo

Classroom is a local-first macOS SwiftUI app (see `classroom_spec.md` for the
product spec). This file is **compiled from the global AI Control modules**
(`~/.ai-control/modules/`: CODING, WORKFLOW, UX, STRUCTURE) and merged with
this project's local rules. To regenerate it, run the rebuild-claude-md
routine. Read it before making changes.

## Coding (CODING.md)

- **Modularize for isolated context.** Write code so any part can be picked up,
  understood, and fixed on its own, without loading the whole system into your
  head. Draw clear module boundaries with small, explicit interfaces; keep
  cross-module coupling low so a change stays contained and a bug has one
  obvious home. In practice: keep `ClassroomCore` split by concern (`Models/`,
  `Services/`, `ViewModels/`) and keep views broken into small, composable
  pieces. If a file is getting hard to hold in your head, split it.
- **Keep it minimal.** Build only what's truly needed. Don't add abstraction,
  configuration, or layers on speculation. Prefer reuse over duplication, but
  don't over-generalize before there's a second real caller.
- **Test what matters.** Cover core logic, risky paths, and anything that would
  silently regress. Skip tests for trivial glue. Phases in a roadmap mostly end
  with tests that lock in what they built.
- **Idiomatic to the ecosystem.** Match Swift/SwiftUI conventions, naming, and
  idioms and the surrounding code. Read the neighbors before writing; new code
  should look like it belongs. Reference code as `file_path:line_number`.

## Workflow (WORKFLOW.md)

- **Commit and back up.** Commit after every working change — small, focused,
  one logical unit per commit; don't batch unrelated edits. Write plain, honest
  messages that say what changed and why. Everything lives on GitHub and is
  pushed regularly; nothing important stays local-only. Commit and push unless
  the user says otherwise. Never commit secrets — `.env` stays in `.gitignore`.
- **Roadmaps and phases.** Any non-trivial update starts with a roadmap broken
  into phases, recorded in the update's `update vX.md`. Most phases end with
  tests that lock in what they built. Track status as you go.
- **Research spikes.** For a new API, unfamiliar library, or genuinely new
  design, make it a research phase: a throwaway spike that runs outside the main
  code, inside the update folder. Capture findings in the update's `wiki.md`.
- **Act as an orchestrator.** Prefer delegating to focused agents over doing
  everything inline: decompose, fan out, synthesize.
- **Verify before moving on.** Verify by running the actual thing, not just a
  green test (see the local verification steps below).

## UX (UX.md)

- **Always bring in UX experts.** For anything with a user-facing surface,
  launch a dedicated UX expert agent to think the experience through. For a
  surface with multiple parts, launch several in parallel, each owning a part,
  and synthesize.
- **Cut everything unnecessary.** Approach every UI as Steve Jobs would:
  relentlessly remove anything that isn't truly needed. The fewest screens,
  controls, and steps that do the job well.
- **Minimal visual system.** Keep fonts, colors, spacing, and sizes to a small,
  deliberate scale — not ad-hoc values. Aim for a polished, modern result.
- **Standardized, reusable, isolated components.** Define a thing once and reuse
  it everywhere. Keep components highly isolated with clear interfaces, mirroring
  the modularity rule above.
- **Fundamentals.** Accessible by default — real contrast, keyboard
  reachability, sensible focus, meaningful labels. Sensible defaults, fast
  feedback, and clear, honest error states over decoration.

## Structure (STRUCTURE.md)

This project carries the AI Control standard scaffold: `.project` (marker with
`modules:`, `secrets:`, `claude_md_generated`), this `CLAUDE.md`, `.gitignore`
(covers `.env`), `updates/`, and `issues.txt`. This project uses no secrets, so
there is no `.env`.

- **Follow the ecosystem's norms.** Keep the standard SwiftPM layout
  (`Sources/`, `Tests/`, `Package.swift`). Keep things flat and simple; add
  folders only when the project genuinely grows into them.
- **The `updates/` folder.** Each update is a folder named
  `updates/YYYY-MM-DD UPDATE_NAME - OPEN/` while in progress and `- CLOSED/`
  when done. Inside: `update vX.md` (goal, phased roadmap, live status; bump
  `X` when the plan is substantially reworked) and `wiki.md` (durable decisions
  and lessons). Only one update should normally be OPEN at a time — ask before
  opening a second.
  - **Local note:** update folders created before adoption (2026-09-23) use the
    older `update.md` (+ optional `roadmap.md`) convention and one uses a
    `- BACKLOG` status. Leave those as they are; new updates follow the standard
    above.

## Local rules (project-specific)

- **Documentation ships with the code.** Code changes ship with the docs that
  describe them: phase/feature checklists in `docs/`, the active update's files
  in `updates/`, and `README.md` when a change affects how the app is built,
  run, or used. Undocumented changes are treated as incomplete.
- **Always build and verify.** Before considering a change finished:
  - `swift build`
  - `swift test`
  - `swift run ClassroomSmokeTests`
  - the relevant manual verification checklist from `docs/` or the active update.
  Then make sure the user is actually running the latest build — rebuild
  `Classroom.app` via `scripts/create-launcher-app.sh` (or the current
  equivalent) so the launcher isn't stale, and tell the user to relaunch it.
  Never report a task complete on the strength of a diff alone.
- **Don't screenshot this app to verify it.** For manual verification, don't
  drive it with screenshots/`screencapture` — ask the user to check instead.
  This is the user's own running app on their own screen (real classroom data,
  not a sandboxed test target), so screenshotting risks capturing whatever else
  is on screen, and the user can just look and tell you directly.

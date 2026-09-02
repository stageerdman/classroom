# Notes / Page Split

## Progress

- **Shipped:** §1 (file split), §2 (edit-mode gating), §3 (top selector +
  split view). `Lesson.notesURL` is gone, replaced by `pageURL`/`noteURL`;
  `ClassroomScanner` resolves `page.md`/`note.md` by exact name and
  migrates a lesson's pre-split markdown file to `page.md` in place
  (`PageMigrationService`). `NotesService`/`PageService` are now thin
  wrappers over a shared `MarkdownFileService`. The lesson pane has a
  `LessonContentSectionSelector` (Page, Notes) feeding `LessonContentPane`,
  which renders one section or both side by side per
  `ContentSectionSelectionService`'s selection rules. `MarkdownNotesView`
  gained `isEditable`; `PageEditorView` uses it to stay read-only outside
  Module edit mode, `NotesEditorView` is always editable.
- **Not yet started:** §4 (timestamped notes), §5 (Obsidian live-preview
  editing — hidden syntax until focused, Cmd-B/I/U, `==highlight==`).

## Goal

Split the lesson pane's single "Notes" section into two distinct sections —
**Page** and **Notes** — selectable via a top category selector, with
support for viewing either one alone or both at once in a split view. Add
timestamped notes that link back to a moment in the lesson's video/audio,
and bring the markdown editor's editing feel closer to Obsidian's live
preview (hidden syntax markers, standard formatting shortcuts, text
highlighting).

## Why

Today's "Notes" section (`ClassroomBrowserView.swift` `notesEditor`,
backed by `NotesService` + `MarkdownNotesView`) conflates two different
things under one editable text box:

- The lesson's **authored content** — written once while building the
  module, meant to be read (not edited) by anyone just watching the
  lesson.
- The viewer's **personal running notes** — should be writable any time,
  including outside of Module edit mode, and is where timestamped
  callouts tied to the video position belong.

Right now both live in whatever single `*.md` file the scanner happens to
find in the lesson folder (`ClassroomScanner.swift`, `notesCandidates`),
defaulting to `Notes.md` (`NotesService.defaultNotesFileName`), and it's
always editable regardless of Module edit mode. There's no per-section
edit gating, no way to anchor a note to a video timestamp, and the
markdown editor shows its syntax markers (dimmed, but always visible) on
every line rather than only the line being edited.

## Current state (for reference)

- `Lesson.notesURL: URL?` (`ClassroomModels.swift:59`) — one optional file
  per lesson, discovered by `ClassroomScanner` as the first `*.md` file in
  the lesson folder.
- `NotesService` (`Sources/ClassroomCore/Services/NotesService.swift`) —
  load/save for that single file, atomic write via temp file + replace.
- `MarkdownNotesView` (`Sources/ClassroomApp/Views/MarkdownNotesView.swift`)
  — `NSTextView`-backed editor; already dims markdown syntax (`##`, `**`,
  `` ` ``, `>`, list bullets) to a small secondary-color prefix, but never
  hides it, and has no highlight mark, no keyboard-shortcut formatting.
- `ClassroomBrowserViewModel.isEditingModule: Bool` — the only edit-mode
  flag in the app; currently ungates everything (drag targets, rename
  fields, etc.) but does not gate Notes editing at all.
- `PlaybackService` (`Sources/ClassroomCore/Services/PlaybackService.swift`)
  — `currentTimeSeconds: Double`, `seek(to:)`, `skipForward/Backward`.
  Exactly what timestamped notes need to read position and jump to one.
- No transcript feature exists yet anywhere in the codebase, and no
  millisecond-precision timestamp format exists (today's only formatter,
  `TimeFormatting.formatPlaybackTime`, rounds to whole seconds for the
  transport bar / scrub preview).

## Scope

### 1. Page / Notes file split

- Introduce `page.md` and `note.md` as the two per-lesson files,
  replacing the single generic-`*.md`-file model.
- **Migration:** whatever file `ClassroomScanner` currently resolves as
  `notesURL` (today's single "Notes" content) becomes the new **Page**
  content — rename/move it to `page.md` on first load after this update.
  A fresh, empty `note.md` is what backs the new **Notes** section. This
  matches how the content is actually being used today (authored lesson
  text, not personal notes), so no content is lost or needs merging.
- `Lesson` gains two URLs (`pageURL`, `noteURL`) in place of the single
  `notesURL`; `ClassroomScanner` and `NotesService` (or a split
  `PageService` / `NotesService` pair) updated accordingly.

### 2. Edit-mode gating

- **Page** is read-only (rendered, not an editable text view) unless
  `viewModel.isEditingModule` is true — matches "this is lesson content,
  authored while building the module."
- **Notes** is always editable, independent of Module edit mode.
- This is the first per-section edit concept in the app; `isEditingModule`
  itself doesn't change meaning, Page just also checks it before
  switching into its editable `MarkdownNotesView` mode.

### 3. Top category selector + split view

- Replace the always-stacked `lessonHeader → mediaPlayer → notesEditor →
  attachmentsSection` layout with a top selector showing categories in
  order **Page, Notes**, above the content area.
- Tapping a category selects it. Tapping a second category while one is
  already selected puts both on screen side-by-side (split view — always
  exactly two panes max). Tapping an already-selected category deselects
  it back to a single view; tapping the only selected category is a
  no-op (never leaves zero categories selected).
- Model this as an ordered selection (`[LessonContentSection]`, capped at
  2) rather than a hardcoded Page/Notes boolean pair, so a future third
  category (e.g. Files) can plug into the same selector without a
  rewrite. Behavior for tapping a third category while two are already
  selected is out of scope for now (only two categories exist) — leave a
  documented seam, decide when it's actually needed.

### 4. Timestamped notes

- **Encoding:** a line-leading marker, Obsidian-callout-flavored:
  `> [!timenote HH:MM:SS.mmm] note text`. Rendered (outside of editing
  that line) as a clickable timestamp pill followed by the note text,
  with the `> [!timenote ...]` syntax hidden the same way other markdown
  syntax is hidden (see §5).
- **Timestamp format:** `HH:MM:SS.mmm` (period-delimited milliseconds,
  WebVTT-style) rather than SRT's comma-delimited variant — unambiguous
  across locales and the more common convention for programmatic/transcript
  tooling. This is the format future transcript ingestion should also
  target, so timestamped notes and transcript cues line up on the same
  clock without a conversion step.
- **Creation, two paths:**
  - **A.** A comment-icon button in the video transport bar
    (`VideoTransportControlsView.swift`) inserts a new timenote line into
    Notes at `PlaybackService.currentTimeSeconds`, switches focus to the
    Notes section (selecting it if not already visible) and places the
    cursor on the new line.
  - **B.** Typing `/timenote` and pressing Enter inside the Notes editor
    (Notion-style slash command) replaces the typed command with the same
    timenote line at the current playback position.
- **Clicking** a rendered timestamp pill calls `PlaybackService.seek(to:)`
  with that time.

### 5. Obsidian-style live-preview editing

- Extend `MarkdownNotesView` so markdown syntax markers (`#`, `**`, `*`,
  `` ` ``, `>`, `> [!timenote ...]`, list bullets) are hidden — not just
  dimmed — for every line except the one currently containing the
  cursor/selection. Clicking into a line reveals its raw markdown;
  clicking away collapses it back to styled text.
- Standard formatting shortcuts: Cmd-B / Cmd-I / Cmd-U wrap the current
  selection (or word under cursor) with `**`/`*`/an underline marker,
  matching macOS text-editing conventions.
- **Highlighting:** adopt Obsidian's `==highlighted text==` syntax,
  rendered with a highlight background (Notion/Obsidian-style), using the
  same hide-syntax-until-focused treatment as everything else.

## Decisions (resolved)

- `page.md` / `note.md` are the fixed filenames (no more generic
  first-`*.md`-found discovery for these two roles).
- Migration maps today's single notes file to **Page**, not Notes.
- Timestamp format for timenotes: `HH:MM:SS.mmm` (period decimal),
  chosen now so a later transcript feature shares the same clock.
- Timenote markdown shape: `> [!timenote HH:MM:SS.mmm] text`.
- Split view is capped at exactly 2 panes; selection model is an ordered
  list to stay extensible to future categories.

## Decisions still open (resolve during implementation)

- Exact mechanics of "hide syntax until line is focused" in `NSTextView`
  — likely collapsing marker characters to near-zero width / transparent
  rather than literally removing them from the text storage, so undo and
  the underlying markdown text stay simple. Needs a prototype before
  committing to an approach.
- Whether split view panes are independently scrollable or share one
  scroll position.
- Behavior when a third selectable category exists and two are already
  selected (no third category ships in this update, so deferred).

## Out of scope (backlog)

- Rendering timestamped notes *during* video playback (e.g. as captions
  or a synced sidebar) — mentioned by the user as a later goal once
  transcripts exist, not part of this update.
- Transcript generation/ingestion itself.

## Verification

- `swift build`, `swift test`, `swift run ClassroomSmokeTests`.
- Add unit coverage for: `page.md`/`note.md` migration from an existing
  single notes file, timenote line parsing/rendering (encode + decode the
  `> [!timenote HH:MM:SS.mmm]` format), and split-view selection toggle
  logic (select / add second / deselect / no-op on last-one).
- Manual (by the user, in-app): confirm Page is read-only outside edit
  mode and editable inside it; confirm Notes is always editable; confirm
  split view shows both panes and single-select/deselect behaves as
  described; confirm both timenote creation paths (comment icon,
  `/timenote`) insert a correct, clickable timestamp that seeks the
  player; confirm markdown syntax hides/reveals per line, Cmd-B/I/U work,
  and `==highlight==` renders.

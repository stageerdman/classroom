# Notes / Page Split

## Closing summary (2026-09-02)

All five scope items shipped and were manually verified by the user.
Verdict on the Obsidian-style formatting polish (§5): "not great, but
okay enough to close" — Page/Notes split, split view, and timenotes all
verified working well; the rich-text formatting shortcuts (Cmd-B/I/U
stacking, in particular) are functional but not polished, with the known
triple-stacking limitation documented below left unresolved by design
(regex-based styling, not a real nested parser — would need a rewrite to
fully fix). Revisit if a proper rich-text editor is adopted later.

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
- **Shipped:** §4 (timestamped notes). `TimenoteFormat`
  (`ClassroomCore/Services`) encodes/parses `> [!timenote HH:MM:SS.mmm]
  text` and formats/parses the `HH:MM:SS.mmm` timestamp itself.
  `MarkdownNotesView` renders the timestamp as a clickable pill (`.link`
  to a `classroom-timenote:<seconds>` URL, intercepted in
  `textView(_:clickedOnLink:at:)`), supports the `/timenote` + Enter
  slash command (`textView(_:shouldChangeTextIn:replacementString:)`
  swaps the typed command for the line prefix in place), and exposes a
  `focusRequest` counter so inserting a timenote from outside the text
  view (the transport bar's new comment-icon button) can move focus/
  cursor into Notes afterward. `ClassroomBrowserViewModel
  .insertTimenoteForSelectedLesson(atSeconds:)` appends the line and
  calls `ensureContentSectionVisible(.notes)`.
- **Shipped:** §5 (Obsidian live-preview editing). `MarkdownNotesView`'s
  styling pass now takes the cursor/selection's line span into account:
  markdown syntax markers (`#`, `**`, `*`, `` ` ``, `>`, `> [!timenote
  ...]`, list bullets, `==`) render at normal small-dimmed size only on
  the line currently being edited; everywhere else they're shrunk to
  near-zero size and made transparent (`markerAttributes(isFocused:)`)
  so only the styled content shows. `==highlighted text==` renders with
  a yellow background via the same delimited-inline-style machinery as
  bold/italic/code. `MarkdownTextView` (a small `NSTextView` subclass)
  intercepts Cmd-B/I/U and wraps/unwraps the current selection with
  `**`/`*`/`<u>...</u>` respectively (toggles off if already wrapped).
- All five scope items are now shipped; remaining work before closing is
  manual verification (see below) and the documentation pass.

## Post-review fixes

First manual verification pass (2026-09-02) found three issues, all fixed:

- **Arrow keys skipped video instead of moving the text cursor** while a
  Page/Notes editor was focused. The transport bar's unmodified Left/
  Right arrow shortcuts (`VideoTransportControlsView`) won the
  `performKeyEquivalent` race against `NSTextView`'s normal cursor
  navigation regardless of first responder. Fixed by tracking editor
  focus (`MarkdownTextView.onFocusChange`, threaded up through
  `MarkdownNotesView` → `PageEditorView`/`NotesEditorView` →
  `ClassroomBrowserView`) and disabling those two shortcuts entirely
  while a text editor has focus (`VideoTransportControlsView
  .disableArrowKeySkip`).
- **Stacking Cmd-B/I/U on the same word broke formatting** — bold (`**`)
  and italic (`*`) share a character, so after bolding a word, applying
  italic to the same (reselected) word saw the adjacent `*` from the
  `**` pair and misidentified it as a standalone italic marker to strip,
  corrupting the bold markup instead of combining the two. Fixed by
  requiring a marker's neighboring character (one further out) *not* be
  the same character before treating it as a clean, standalone delimiter
  (`Coordinator.isMarkerCharacter(at:matching:in:)`); stacking now
  correctly produces `***word***`-style combined markup.
- **Bolding/italicizing text inside a header line shrank it back to
  normal body size** — the inline bold/italic/code/highlight styling
  pass ran after (and overwrote) the header's whole-line font, since it
  matches by regex across the whole document rather than per line.
  Fixed by collecting header line ranges during the line-by-line pass
  and skipping any inline match that overlaps one, so a header's font
  size is never overwritten. Trade-off: `**`/`*`/etc. markers *inside* a
  header line no longer get the hide-until-focused treatment (they stay
  visible at the header's size/color) — an edge case (bolding text
  within a heading) traded for fixing the more disruptive font-collapse.

Second pass (same day) found the arrow-key and header fixes held, but
stacking still broke — root cause was different from what the marker-
boundary fix above addressed:

- **Underline (`__text__`) had no visual rendering at all.** Cmd-U
  correctly inserted the `__` markup, but no styling pass recognized it,
  so `applyMarkdownStyle` never touched it directly — it just fell
  through to whatever *other* pattern's regex happened to also match
  across it (italic's `[^*]+` content class doesn't exclude
  underscores, so it silently swallowed an entire `__text__` span as
  plain italic content). Stacking bold → italic → underline on a word
  landed on this exact case: the underline step never ran, so the
  visible result reflected only whichever pattern won the swallow.
  Fixed with a dedicated `applyUnderlineStyle` pass — deliberately the
  only inline pass that touches *just* `.underlineStyle` and never
  font/color, so it composes with an overlapping bold/italic/code match
  instead of overwriting it, regardless of pass order.
- Remaining known limitation: bold **and** italic **and** underline all
  at once on the same word may still not render with all three traits
  visible simultaneously, because italic's regex requires asterisk-free
  content and therefore can't match when bold's `**` is nested inside
  it — a real limitation of independent regex passes rather than a
  proper nested parser. Pairwise combinations (any two of bold/italic/
  underline) render correctly; the underlying markdown text is always
  valid regardless. A full fix would mean replacing the regex passes
  with a real recursive tokenizer — out of scope here unless requested.

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

- Whether split view panes are independently scrollable or share one
  scroll position — currently they share one, since both panes live in
  the same outer `ScrollView` in `ClassroomBrowserView.detail`.
- Behavior when a third selectable category exists and two are already
  selected (no third category ships in this update, so deferred).

## Resolved during implementation

- "Hide syntax until line is focused" landed as: marker characters keep
  their normal small-dimmed styling on the line touching the
  cursor/selection, and shrink to a near-zero-size, transparent font
  everywhere else (`MarkdownNotesView.Coordinator.markerAttributes
  (isFocused:)`) — they stay in the text storage (so undo and the
  underlying markdown text stay simple), just rendered invisible.

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

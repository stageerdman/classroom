# BlockNote Editor

## Goal

Replace the native `NSTextView`-based Page/Notes editor with
[BlockNote](https://github.com/TypeCellOS/BlockNote) for real — the user
greenlit this after trying the spike (see
`updates/2026-09-02 BLOCKNOTE-SPIKE - CLOSED/update.md`). `page.md`/
`note.md` stay ordinary Markdown files on disk; BlockNote is purely the
in-app editing surface, converting to/from Markdown so nothing else in
the app (file services, autosave, the split-view selector) needs to know
the editing widget changed.

## Design

- **Storage stays plain Markdown.** `PageService`/`NotesService`/
  `MarkdownFileService` are untouched. `BlockNoteEditorView` takes the
  same `text: Binding<String>` contract `MarkdownNotesView` did — on the
  way in, the web app calls `editor.tryParseMarkdownToBlocks(markdown)`;
  on change (debounced), `editor.blocksToMarkdownLossy()` posts the new
  markdown back to Swift, which writes it through the exact same
  autosave path as before (`scheduleNoteAutosave`/`schedulePageAutosave`
  → `saveSelectedNoteIfNeeded`/`saveSelectedPageIfNeeded`).
- **Timenotes became plain CommonMark links**, not a custom BlockNote
  block type: `[HH:MM:SS.mmm](classroom-timenote:<seconds>) note text`.
  A custom block schema would need custom markdown
  serialization/parsing rules and is real ongoing version-coupling risk;
  a standard link round-trips through BlockNote's built-in markdown
  conversion with zero special-casing, and BlockNote already renders
  links as clickable text. A `document`-level capture-phase click
  listener in the web app intercepts clicks on `classroom-timenote:`
  hrefs (preventing BlockNote's default "treat it as a real link"
  behavior) and posts the timestamp to Swift instead. This is a *visual
  format change* from the previous native editor's `> [!timenote
  HH:MM:SS.mmm] text` callout syntax — acceptable since there's no
  meaningful body of existing timenotes yet.
- **Bridge contract** (`BlockNoteEditorView.swift` ↔
  `webviews/blocknote-editor/src/App.tsx`):
  - JS → Swift, via `WKScriptMessageHandler` named `classroomBridge`:
    `{type: "ready"}` (once mounted), `{type: "contentChanged",
    markdown}` (debounced 400ms), `{type: "timenoteClicked", seconds}`.
  - Swift → JS, via `webView.evaluateJavaScript` calling functions Swift
    itself attached to `window.classroomBridge`: `loadMarkdown(markdown,
    editable)`, `setEditable(editable)`, `insertTimenoteAtEnd(seconds)`,
    `setCurrentPlaybackSeconds(seconds)`.
  - `BlockNoteEditorView.Coordinator` guards against feedback loops the
    same way `MarkdownNotesView`'s old NSTextView-based version did:
    only pushes a full `loadMarkdown` reload when the incoming `text`
    prop differs from the last markdown *the editor itself* reported —
    otherwise every keystroke would round-trip through a full
    reparse-and-replace.
- **`/timenote` slash command** reads a Swift-pushed
  `currentPlaybackSeconds` value (refreshed reactively whenever
  `PlaybackService.currentTimeSeconds` changes while Notes is visible)
  rather than round-tripping to Swift synchronously at slash-command
  time.
- **Focus tracking** for the arrow-key-vs-video-skip fix from the native
  editor carries over: `BlockNoteWebView` (a `WKWebView` subclass)
  overrides `become/resignFirstResponder`, mirroring
  `MarkdownTextView.onFocusChange`.
- **Fixed editor height** (420pt, scrolls internally) replaces the old
  NSTextView's auto-measured-from-content height — WKWebView doesn't
  expose content height without another JS↔Swift round trip
  (`ResizeObserver` + bridge message), and that felt like scope creep
  for this pass. Worth revisiting if the fixed height feels cramped.
- **Everything else about Page/Notes is unchanged**: the top selector,
  split view, edit-mode gating for Page, drag-and-drop file-link
  insertion into Notes (still works — it mutates `noteText` directly,
  which triggers the same "external change, full reload" path as
  switching lessons).
- `MarkdownNotesView`/`MarkdownTextView` (the native editor) are kept
  as-is for `MarkdownFileSheet` — opening an arbitrary `.md` ghost/
  attachment file while editing still uses the lightweight native
  editor, not BlockNote. That's a one-off viewer for random files, not
  the main editing surface, so there's no reason to pay BlockNote's
  weight there. `TimenoteFormat.swift` (Swift) stays too, since
  `MarkdownNotesView` still renders/hides `> [!timenote ...]` lines if
  it happens to open a file containing one.

## What shipped

- `webviews/blocknote-editor/` — the real web app (supersedes and
  replaces `webviews/blocknote-spike/`, which is deleted): BlockNote
  editor, the bridge, the timenote link format + click interception, the
  `/timenote` slash menu item.
- `BlockNoteSchemeHandler` generalized to take a configurable resource
  subdirectory (was hardcoded to the spike's).
- `BlockNoteEditorView.swift` — the real `NSViewRepresentable` + bridge,
  replacing `BlockNoteSpikeView`/`BlockNoteSpikeWindowController` (both
  deleted, along with the dev-only menu item and
  `Resources/BlockNoteSpike/`).
- `PageEditorView`/`NotesEditorView` now use `BlockNoteEditorView`
  instead of `MarkdownNotesView`.
- `ClassroomBrowserViewModel.insertTimenoteForSelectedLesson(atSeconds:)`
  removed — timenote insertion now happens inside the WebView via the
  bridge (`insertTimenoteAtEnd`), not by Swift mutating `noteText`
  directly. `ensureContentSectionVisible(_:)` stays, still called from
  the transport bar's comment-icon handler.
- `scripts/build-blocknote-editor.sh` (replaces
  `build-blocknote-spike.sh`).

## Known gaps / follow-ups

- Fixed 420pt editor height rather than auto-sizing to content (see
  Design above) — revisit if it feels cramped in practice.
- No automated test coverage for the bridge itself (JS↔Swift message
  round-trips) — this is UI/WebView-level behavior, consistent with how
  `MarkdownNotesView`'s AppKit-level behavior was never unit tested
  either; relies on manual verification.
- Bundle size (~12MB, mostly Shiki code-block language grammars) carried
  over from the spike — still not trimmed.

## Verification

- `swift build`, `swift test`, `swift run ClassroomSmokeTests`.
- Manual (by the user, in-app — this is the bulk of verification here
  given how much of the new behavior lives inside the WebView):
  - Open a lesson with existing Page/Notes content — confirm it loads
    correctly into BlockNote (markdown → blocks conversion).
  - Type in both Page (while in Module edit mode) and Notes (always) —
    confirm autosave still writes plain markdown to `page.md`/`note.md`.
  - Confirm Page is read-only outside edit mode.
  - Comment-icon button in the transport bar inserts a timenote at the
    end of Notes and focuses it; typing `/timenote` inside Notes inserts
    one inline at the cursor.
  - Clicking a rendered timenote timestamp seeks playback.
  - Arrow keys move within BlockNote's text instead of skipping video
    while it's focused; skip video otherwise.
  - Dropping a file onto Notes while editing still inserts a link.
  - Switch between lessons and confirm content reloads correctly instead
    of leaking the previous lesson's text.

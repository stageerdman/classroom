# Markdown Engine

## Goal

Replace the app's hand-rolled `NSTextView` + regex Obsidian-style live-preview
styler (`MarkdownNotesView`) with
[swift-markdown-engine](https://github.com/nodes-app/swift-markdown-engine) —
a native, TextKit 2–backed macOS markdown editor package. This is the user's
explicit pick, made after `updates/2026-09-02 BLOCKNOTE-SPIKE - CLOSED/update.md`
concluded the BlockNote (web/React) direction "wasn't good" and was reverted.

## Why

The current editor's complaints, from the user directly: laggy, and "obsidian
like" (raw markdown syntax visible) — they want "a solid editing experience,
without seeing the code." The custom implementation re-styles the *entire*
document with several regex passes on every keystroke, which is both the
performance problem and (via its whole-line reveal-on-focus behavior) the
"obsidian like" one. swift-markdown-engine is a mature, real package (not a
spike candidate) — TextKit 2 native, no WebView/Node/JS bridge, MIT-adjacent
Apache 2.0 license, macOS 14+ (matches this app's deployment target already).

## What shipped

- Removed all BLOCKNOTE-SPIKE leftovers: the dev-only WKWebView spike window,
  scheme handler, its bundled JS build, and the `webviews/blocknote-spike`
  Node project. That direction is fully closed; this update starts clean.
- Added `swift-markdown-engine` as a Package.swift dependency and swapped
  `MarkdownNotesView` from an `NSViewRepresentable` that owned an `NSTextView`
  directly to a thin wrapper around the package's `NativeTextViewWrapper`.
  All three call sites (`PageEditorView`, `NotesEditorView`,
  `MarkdownFileSheet`) are unchanged — the external API
  (`text`/`contentHeight` bindings, `onTextChange`, `isEditable`,
  `onTimenoteSlashCommand`, `onTimenoteClick`, `focusRequest`,
  `onFocusChange`) is preserved so the blast radius stays inside one file.
- Timenotes (`> [!timenote HH:MM:SS.mmm] text`) are re-encoded as a custom
  `MarkdownDirective` — `> @timenote(at: SECONDS){HH:MM:SS.mmm} text` — see
  "Timenote design" below for why. `TimenoteFormat` gained
  `migratingLegacySyntax(in:)`, run once when a `page.md`/`note.md` loads, so
  existing lesson notes upgrade to the new syntax transparently on first open
  (and are written back in the new format on next save).

## Timenote design

swift-markdown-engine has no documented hook for clicking arbitrary custom
syntax — only two things are wired to click callbacks:
`NativeTextViewWrapper.onLinkClick`, which fires for `[[wiki-links]]` *and*
for any span carrying a `String`-valued (not `URL`-valued) `.link` attribute
text attribute, routed through the same `clickedOnLink` delegate path
(confirmed by reading `NativeTextViewCoordinator+TextDelegate.swift` and
`WikiLinkService.resolveIdentifier` directly — this isn't documented in the
README/ARCHITECTURE.md).

Directives (`MarkdownDirective`) are the only seam that both (a) carries
per-instance typed arguments and (b) can attach that `.link` attribute to
*always-visible* content — a directive's body (`{...}`) gets an embedder's
attributes applied permanently; only the marker/argument prefix
(`@timenote(at: 752.567)`) gets the engine's generic caret-reveal muting.
So: the numeric seconds live in the muted, hidden-unless-editing directive
arguments, and the human-readable `HH:MM:SS.mmm` pill — the part that must
stay visible and clickable regardless of caret position — is the directive's
body. `TimenoteDirective.swift` (`Sources/ClassroomApp/Markdown/`) sets
`.link: "classroom-timenote:<seconds>"` (a `String`, not a `URL` — this is
load-bearing, see above) plus the pill's font/colors on that body range.
`MarkdownNotesView` parses the `classroom-timenote:` prefix back out of
`onLinkClick`'s target string.

## Known gaps (verify these specifically)

swift-markdown-engine's public API (`NativeTextViewWrapper` + its
`Coordinator`) has no cursor-position or first-responder control, and no
focus-change callback — confirmed by reading the actual source, not just
docs. Two interactions built on the old direct `NSTextView` access are
affected:

- **`/timenote` + Enter slash command**: reimplemented via `onTextMutation`
  (fires after the engine commits an edit) — detects the completed
  `/timenote\n` insertion and swaps it for the directive line in the `text`
  binding. This *should* look instant, but there's no guarantee about where
  the caret lands afterward (no API to place it) — needs a manual check.
- **Focus-after-insert and arrow-key guard**: `focusRequest` (jump into Notes
  and place the caret at the end after the transport bar's comment button
  inserts a timenote) and `onFocusChange` (disable the video transport bar's
  arrow-key skip while text is focused) have **no engine equivalent** and are
  currently no-ops. The types under `NativeTextViewContainer`/`NativeTextView`
  that would need reaching into aren't `public`, so there's no safe way to
  wire these without depending on the package's private internals. Until the
  package adds a focus/cursor API (or we decide reaching into internals is
  worth the fragility), inserting a timenote from the transport bar no longer
  auto-focuses Notes, and arrow keys may skip video playback while typing.

## Verification

- `swift build`, `swift test`, `swift run ClassroomSmokeTests`.
- Manual (by the user, per this app's own rule against screenshotting real
  lesson data):
  - Typing bold/italic/headers/lists/code/links in both Page and Notes reads
    as fast and WYSIWYG, no visible lag.
  - Existing lesson notes with old-style `> [!timenote ...]` lines still show
    a clickable, correctly-seeking timestamp pill after opening (migration).
  - New timenotes via the transport bar's comment button and via typing
    `/timenote` + Enter both produce a working pill.
  - The two known gaps above, specifically: does losing auto-focus-on-insert
    and the arrow-key guard actually bother you in practice?

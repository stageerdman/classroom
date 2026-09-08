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

## Formatting shortcuts, right-click menu, and focus tracking (second pass)

The first pass above shipped with three regressions from the old editor,
found by the user testing it: Cmd-B/Cmd-I did nothing, `==highlight==` had no
visual effect, right-click showed no formatting options, and — reported
separately — arrow keys inside a focused editor were skipping video instead
of moving the caret (the "arrow-key guard" gap called out below, now fixed).

**Root cause of the first three**: `NativeTextViewWrapper` ships its own
formatting logic (`didMarkdownBold`, `didMarkdownItalic`, `didMarkdownHighlight`,
`didMarkdownStrikethrough`, `didMarkdownInlineCode`, `didMarkdownBlockquote`,
list/heading/link/image/code-block/horizontal-rule actions — all in the
upstream `ContextMenu.swift`, despite the name) on its coordinator, correctly
handling cases the old hand-rolled Cmd-B/I/U toggle got wrong (e.g.
`***both***` → toggle bold → `*italic*`, not a mangled string — this directly
fixes the "stacking" problem raised alongside this request). But the engine
deliberately ships **no menu and no keyboard shortcuts** — `onBuildContextMenu`
exists precisely so an embedder adds its own menu items calling those actions,
and nothing wires keyboard shortcuts at all. `==highlight==`/`~~strikethrough~~`
additionally need `HighlightExtension`/`StrikethroughExtension` *registered*
on the configuration to render and toggle correctly — without them the
actions still insert `==`/`~~` characters, they just don't mean anything to
the parser. None of this was wired in the first pass; it is now:

- `MarkdownEditorConfiguration.extensions` now includes `HighlightExtension()`
  and `StrikethroughExtension()`.
- `MarkdownFormattingAction.swift` (`Sources/ClassroomApp/Markdown/`) dispatches
  to the engine's `didMarkdown*` actions by raw `Selector` — they're `@objc`
  but not `public`, so a compile-time `#selector(...)` reference isn't
  possible from this module; `NSObject.perform(_:with:)` is the standard,
  sanctioned way to call an `@objc` method whose Swift access level would
  otherwise block it, since Swift access control only gates the compiler's
  static member lookup, not Objective-C message dispatch. Same file builds
  the right-click formatting menu (headings 1–6, bold, italic, highlight,
  strikethrough, inline code, blockquote, lists, link, image, code block,
  horizontal rule) that the engine no longer ships one for.
- A new "Format" menu in `ClassroomApp.swift` gives Bold/Italic/Highlight/
  Strikethrough/Inline Code real keyboard shortcuts, broadcast via
  `NotificationCenter` (same pattern this file already uses for Undo/Redo) —
  necessary because the engine's coordinator isn't part of the AppKit
  responder chain, so a menu item with no explicit `target` can't reach it.
  Whichever editor currently has focus picks up the broadcast; see below for
  how "currently has focus" is known at all.

**The underlying blocker for all of this, and for the two gaps flagged in the
first pass**: none of it is reachable without a direct reference to the
specific `NSTextView` instance `NativeTextViewWrapper` mounts internally —
menu items need a `target`, and focus/cursor control needs the view itself —
and the package's public API hands back neither. `MarkdownTextViewLocator.swift`
solves this by walking the AppKit view hierarchy from a `.background()`
overlay to find the nearest real `NSTextView`, using only public AppKit types
(`NSView.subviews`, casting to `NSTextView`) — no private type names, since
`NativeTextView`/`NativeTextViewContainer` aren't `public` and can't be named
from this module anyway. This is *load-bearing but structural*: it assumes
`.background()` content stays positioned close to `NativeTextViewWrapper` in
the view tree (already relied on for the `contentHeight` measurement below)
and that swift-markdown-engine keeps mounting a real `NSTextView` somewhere
under its `NSScrollView`. **Verify Page and Notes both visible in a split
view don't cross-wire** (formatting/focus intended for one affecting the
other) — the search is bounded and first-match-wins specifically to make
that unlikely, but it hasn't been checked against the real split-view layout.

With a real `NSTextView` reference in hand, the two gaps from the first pass
are now fixed the same way:
- **Focus-after-insert**: `focusRequest` now calls
  `window?.makeFirstResponder(textView)` + `setSelectedRange(...)` directly.
- **Arrow-key guard**: `onFocusChange` now fires from `NSText.didBeginEditingNotification`/
  `didEndEditingNotification`, scoped via `object:` to this editor's specific
  text view — not a global broadcast, which would also fire for unrelated
  fields elsewhere in the app (lesson/category rename, the folder-path field)
  and incorrectly block the video transport's arrow-key skip while someone's
  renaming something.

**Not carried over**: the old Cmd-U underline (`__text__` via inline HTML —
CommonMark has no native underline syntax). swift-markdown-engine has no
underline action at all, and the request was to match the library, not add
something on top of it.

## Cmd-Z/Cmd-Shift-Z: text undo vs. folder-structure undo

`ClassroomApp.swift` unconditionally replaced the system Undo/Redo menu
items with ones posting `.undoEditRequested`/`.redoEditRequested` — broadcasts
`ClassroomBrowserView` turns into calls on `ClassroomBrowserViewModel`'s own
`UndoManager`, which tracks folder/lesson-structure edits (renames, moves,
transforms). Because a *menu item's* key equivalent takes priority over
whatever the focused view would otherwise do with the same keystroke, this
meant Cmd-Z/Cmd-Shift-Z always hit folder-structure undo — even while
focused in Page/Notes wanting to undo a text edit instead.

Fixed by trying the standard `undo:`/`redo:` action via the responder chain
first (`NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)`) — this is
exactly what the system's *default*, un-replaced Undo/Redo menu items would
do, and it's what `NSTextView` (swift-markdown-engine's included, via
`allowsUndo = true` and its own per-document `UndoManager`, so text undo
stays correctly scoped to whichever document's editor is focused) and any
plain `NSTextField`-backed field (lesson/category rename, etc.) already
implement for free. Only when nothing in the responder chain claims it —
i.e. no text field is focused — does it fall back to the folder-structure
broadcast. No `isEditingModule` gate was needed on the folder-undo side: its
`UndoManager` only ever has actions pushed onto it by edits that already only
happen in Module edit mode, so it's naturally empty (a no-op) otherwise.

## Verification

- `swift build`, `swift test`, `swift run ClassroomSmokeTests`.
- Manual (by the user, per this app's own rule against screenshotting real
  lesson data):
  - Typing bold/italic/headers/lists/code/links in both Page and Notes reads
    as fast and WYSIWYG, no visible lag.
  - Existing lesson notes with old-style `> [!timenote ...]` lines still show
    a clickable, correctly-seeking timestamp pill after opening (migration).
  - New timenotes via the transport bar's comment button and via typing
    `/timenote` + Enter both produce a working pill, and typing continues
    naturally where the slash command left the cursor.
  - Cmd-B, Cmd-I, Cmd-Shift-H (highlight), Cmd-Shift-X (strikethrough),
    Cmd-E (inline code) all apply/toggle correctly, including on a selection
    that already has one of the others applied (the old stacking bug).
  - Right-click inside Page/Notes shows the new formatting section and each
    item works.
  - Clicking the comment-bubble button in the transport bar focuses Notes
    with the caret at the end, ready to type.
  - With only Page or only Notes open, arrow keys move the caret while
    editing and skip video playback everywhere else, as before.
  - **With Page and Notes both open in a split view**, formatting/arrow-key
    behavior in one doesn't leak into the other — the specific thing to
    watch for given the view-hierarchy search above.

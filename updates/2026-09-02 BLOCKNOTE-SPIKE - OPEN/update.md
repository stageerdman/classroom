# BlockNote Spike

## Goal

Evaluate [BlockNote](https://github.com/TypeCellOS/BlockNote) — a
React/TypeScript block-based rich text editor (built on ProseMirror) — as
a possible future replacement for the app's native `NSTextView`-based
Page/Notes editor. This is a **spike**: prove out embedding it and get a
feel for the interaction quality, without touching real lesson data or
committing to the architecture change yet.

## Why

The user pointed at BlockNote as having "figured out the perfect
experience of working with .md files" after using the current native
editor (see `updates/2026-09-02 NOTES-PAGE-SPLIT - CLOSED/update.md`,
whose closing note calls the Obsidian-style formatting polish "not
great"). BlockNote is not a Swift library — it's a web (React) component
— so adopting it for real means embedding a `WKWebView` running a bundled
React app, a JS↔Swift bridge, a new Node/npm build dependency, and
rebuilding timenotes/highlighting/etc. as custom BlockNote blocks. That's
a multi-day rewrite, not an add-on. Before committing to it, this spike
answers: does it actually feel better once embedded in this app, and is
embedding it even straightforward.

## Scope (spike only — no file/timenote integration)

- A small Node/npm project (`webviews/blocknote-spike/`) — React +
  Vite + `@blocknote/core`/`@blocknote/react`/`@blocknote/mantine` —
  building to a static `dist/` bundle (HTML/JS/CSS, no server needed).
- The built bundle copied into `Sources/ClassroomApp/Resources/
  BlockNoteSpike/` so `swift build` never needs Node — only rerunning the
  build script does, when the spike's web code changes.
- A `BlockNoteSpikeView` (`WKWebView`-backed `NSViewRepresentable`) that
  loads `index.html` from that bundled resource directory.
- A new secondary `WindowGroup` scene + menu item ("Window ▸ BlockNote
  Spike" or similar) to open it — isolated from the real lesson UI
  entirely, easy to rip out if the spike doesn't pan out.
- Explicitly **not** in scope: loading/saving `page.md`/`note.md`,
  timenote rendering/click-to-seek, `/timenote` slash command, any
  bridge between Swift and the WebView beyond just displaying it. This
  is purely "does the editor feel good and is embedding it tractable."

## Decisions

- Bundle output is committed to the repo (built once, checked in) rather
  than requiring Node at `swift build` time — keeps the existing
  Node-free build working for anyone who isn't touching this spike.
- Scoped to a dev-only window, not wired into the real lesson pane, per
  the user's choice — keeps this reversible and low-risk while
  evaluating.

## Findings so far

- Embedding needs a custom `WKURLSchemeHandler`, not
  `WKWebView.loadFileURL`. WebKit refuses to load `<script
  type="module">` (what Vite's build output always uses) over `file://`
  — there's no origin for it to key CORS off of, so the page loaded but
  the module script silently failed, leaving a blank white window with
  no visible error. Fixed with `BlockNoteSchemeHandler`, which serves the
  bundled files over a custom `classroom-blocknote://` scheme instead —
  still fully local/offline, just with a real origin WebKit accepts.
- **Bundle size is real**: the default BlockNote setup (via
  `@blocknote/mantine`) pulls in Shiki syntax highlighting for code
  blocks, which alone accounts for the bulk of a ~12 MB / ~317-file
  build (one small JS chunk per supported language). Worth revisiting
  before going further — either disable/lazy-load code-block
  highlighting, or accept the size for a local-first desktop app where
  it doesn't matter much.

## Verification

- `swift build`, `swift test`, `swift run ClassroomSmokeTests` all still
  pass with no Node/npm involvement.
- Manual (by the user): open the new window, confirm the BlockNote editor
  loads and is usable (typing, slash menu, formatting) inside the
  WKWebView.

## Next steps (if the spike looks good)

To be scoped as a separate, much larger update if greenlit: JS↔Swift
bridge for load/save, migrating `page.md`/`note.md` handling (plain
markdown vs. BlockNote's native JSON block format), a custom BlockNote
block type for timenotes with click-to-seek, and replacing
`PageEditorView`/`NotesEditorView` for real.

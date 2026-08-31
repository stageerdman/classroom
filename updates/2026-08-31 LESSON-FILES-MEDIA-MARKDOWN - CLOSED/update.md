# LESSON-FILES-MEDIA-MARKDOWN

**Status:** CLOSED
**Opened:** 2026-08-31
**Closed:** 2026-08-31

## Goal

Third round from the CORE 100 testing session. Three requests:

1. Be able to open a lesson and operate with the files/folders inside it
   — not just see them listed.
2. `video.flv` wasn't recognized as a lesson's media.
3. Markdown should render live in-app — headers, etc. — "similar dynamic
   to Obsidian."

## What shipped

### 1. Lesson-level files/folders are now fully browsable and operable

The lesson detail pane's "Other Files In This Lesson" section previously
rendered ghosts as flat, inert rows (drag-only, via a raw `URL`
transferable). It now reuses `GhostEntryRow` — the same component built
for the sidebar's ghost browsing — so a folder inside a lesson expands
recursively to show what's in it, files/folders can be dragged into
another folder (a category, another ghost folder, or the lesson's own
Attachments drop zone, which now also accepts the ghost-string drag
payload alongside native Finder drags) to reorganize, and clicking a file
opens it. `GhostEntryRow` gained `allowsTransform: Bool` (defaulting to
`true`) — off for lesson-scoped ghosts, since a folder inside a lesson
can't become a nested lesson (no such concept in this data model); on
everywhere else, unchanged.

Clicking a ghost or attachment file now opens it — Markdown files open
in-app (see #3 below); everything else opens in whatever app macOS has
associated with it, same as attachments already did.

### 2. `.flv` recognition + an honest error instead of a silent dead player

`ClassroomScanner.defaultMediaExtensions` gained `flv`, so a lesson built
around one is recognized and picked as its media rather than silently
read as having no media (and the `.flv` file itself showing up as an
unexplained stray/ghost). But macOS's AVFoundation has never had an FLV
demuxer, so simply recognizing the extension isn't enough — without more,
the file would be "chosen" and then fail to play with no clear signal why.
`PlaybackService` now observes `AVPlayerItem.status` and, on `.failed`,
clears the player and surfaces the underlying error; `.flv` specifically
is short-circuited before even attempting AVFoundation (added to
`PlaybackService.knownUnplayableContainerExtensions`) with a message that
names the actual problem: "FLV isn't supported by macOS's built-in video
player (AVFoundation has no FLV demuxer). Convert it to MP4 or MOV to play
it here." Other exotic containers (AVI, WMV, MKV) have the same underlying
AVFoundation limitation if this comes up again — not proactively added
since only `.flv` was reported, but the fix generalizes trivially by
extending `knownUnplayableContainerExtensions`.

### 3. Obsidian-style live Markdown styling

`MarkdownNotesView` already did *some* of this (headers/bold/italic got a
bigger/bolder font applied to the whole line, marker characters included)
but the markers competed at full size/weight with the content, and lists,
checkboxes, blockquotes, inline code, and links weren't styled at all.
Rewrote the styling pass:

- Headers `#` through `######`, blockquotes `>`, checkboxes `- [ ]`/
  `- [x]` (checked items get struck through and dimmed), plain list
  bullets `-`/`*`/`+`, and horizontal rules (`---`/`***`/`___`) are all
  recognized line-level constructs.
- Inline bold `**x**`, italic `*x*`, code `` `x` ``, and links
  `[text](url)` (clickable via Cmd-click, standard AppKit `.link`
  behavior) are recognized inline constructs.
- In every case the syntax marker itself (the `##`, `**`, `` ` ``,
  `[`/`](url)`) is dimmed to a small secondary-color prefix/wrapper rather
  than matching the content's size and weight — that's the actual
  "Obsidian dynamic" the request asked for: the raw syntax fades into the
  background and the rendered content is what reads as the heading/quote/
  link, while the underlying text (and thus the saved `.md` file) is still
  exactly what you typed, since this only ever restyles — the text storage
  itself is untouched.
- This is used by both the lesson notes editor and the new
  `MarkdownFileSheet` (opens any Markdown ghost/attachment in the same
  editor via `NotesService.loadNotes(at:)`/`saveNotes(to:)`, which already
  worked with arbitrary URLs, not just a lesson's designated notes file).

## Verification

- `swift build` — clean.
- `swift run ClassroomSmokeTests` — passed; extended with a scanner check
  that a `.flv`-only lesson resolves it as `mediaURL`, and a
  `PlaybackService` check that loading a `.flv` short-circuits to no
  player with an error message naming FLV specifically. (Caught and fixed
  a real test-fixture ordering bug along the way: adding the new `.flv`
  lesson next to the existing "Welcome" fixture shifted natural-sort
  order, breaking an index-based assertion — switched it to look up by
  title instead of assuming position.)
- `swift test` — compiles; no `xctest` runner in this sandbox, same
  standing note as prior updates.
- **Not verified in this session** (no way to drive a macOS GUI here):
  the actual visual Markdown styling (header sizes, dimmed markers,
  checkbox strikethrough, link Cmd-click), the recursive lesson-ghost
  browsing/drag-and-drop feel, and the `MarkdownFileSheet` sheet's
  save/load round-trip through the real UI. `MarkdownNotesView` has no
  automated coverage at all (it's a pure `NSViewRepresentable`, nothing
  in `ClassroomCore` to smoke-test against) — run through the manual
  checklist by hand before trusting the rendering.

<p align="center">
  <img src="Sources/ClassroomApp/Resources/classroom-icon.png" alt="Classroom logo" width="96" height="96">
</p>

# Classroom

A local-first macOS app that turns any folder into a browsable classroom —
no upload, no duplication, no server. The folder structure is the source of
truth: folder names become classrooms, modules, categories, and lessons.

Opening a classroom shows a gallery of module cards (name, description,
progress); opening a module reveals the same sidebar of categories and
lessons it always has. Right-clicking a module card (or the **Edit** button
in an open module's sidebar) turns on editing directly in that same view —
no separate editor screen. While editing you can rename the module,
categories, and lessons in place; create new ones; drag a lesson to
reorder or reparent it across categories; transform a plain folder into a
lesson; Trash a category or lesson; and drop files onto a selected lesson's
media, notes, or attachments. Right-clicking any lesson — editing or not —
also offers **Reveal in Finder**, which opens the lesson's folder on disk.
See `classroom_spec.md` for the
original product and engineering spec,
`updates/2026-08-30 GALLERY-LESSON-FOLDERS - CLOSED/update.md` for the
gallery/lesson-folder update,
`updates/2026-08-30 MODULE-EDITOR - CLOSED/update.md` for the editor, and
`updates/2026-09-02 NOTES-PAGE-SPLIT - CLOSED/update.md` for the Page/Notes
split and timenotes, and
`updates/2026-10-15 TRANSCRIPT - OPEN/update v1.md` for the transcript tab.

## Structure

```text
Classroom Root/                  Depth 1: Classroom
├── Module A/                     Depth 2: Module
│   ├── description.md            Optional — module card description
│   ├── Lesson 1/                  Depth 3: Direct lesson folder
│   │   ├── .lesson                 Hidden marker — this folder is a lesson
│   │   ├── Lesson 1.mp4            At most one playable media file
│   │   ├── Lesson 1.md             Optional transcript (named like the media)
│   │   ├── page.md                 Authored lesson content (edit-mode only)
│   │   ├── note.md                 The viewer's own notes (always editable)
│   │   └── Attachments/            Optional — files attached to the lesson
│   │       └── Handout.pdf
│   └── Category A/                Depth 3: Category (no marker file)
│       └── Lesson 2/               Depth 4: Lesson folder
│           ├── .lesson
│           └── Lesson 2.mov
└── Module B/
```

A folder is a **Lesson** if it directly contains a hidden `.lesson` marker
file — that's what lets a Lesson folder and a Category folder coexist at
the same depth. A Lesson folder holds at most one playable media file
(`.mp4`, `.mov`, `.m4v`, `.mp3`, `.m4a`, `.wav`, `.flv`), an optional
transcript (a `.md` file named like the media — see **Transcript** below), a
`page.md`, a `note.md`, and an optional `Attachments/` folder; attachments
only show up in the UI when that folder is present and non-empty. Removing an
attachment from the editor moves it into a `Removed/` folder inside that
lesson rather than deleting it — visible in the editor's raw file tree,
invisible to normal browsing, same as `Attachments/` is until it's the
recognized folder.

`.flv` is recognized so a lesson built around one isn't silently treated
as having no media, but macOS's AVFoundation has no FLV demuxer — playing
one shows a clear "convert it to MP4 or MOV" message rather than a silent
dead player. Any other file or folder sitting in a lesson's folder besides
its chosen media, `page.md`/`note.md`, and `Attachments/`/`Removed/` shows
up while editing as a dimmed "ghost" entry; ghost folders (anywhere —
module, category, or inside a lesson) open to browse their contents
recursively, and files/folders can be dragged between them to reorganize.
A lesson from before the Page/Notes split (a single arbitrary `.md` file)
has that file renamed to `page.md` automatically the first time it's
scanned.

### Page and Notes

A lesson's content area has a top selector — **Page**, **Notes**, and
**Transcript** (the last only when the lesson has a transcript file). The
video/audio player stays pinned at the top while the selected section(s)
scroll below it (each editor keeps its caret in view as you type);
attachments sit as a strip beneath. Selecting one section shows it
full-width; selecting two splits the pane in two. **Page** (`page.md`) is the lesson's authored
content: read-only unless the containing Module is in edit mode. **Notes**
(`note.md`) is the viewer's own running notes: always editable, in or out
of edit mode.

Both editors are backed by
[swift-markdown-engine](https://github.com/nodes-app/swift-markdown-engine),
a native TextKit 2 editor — see
`updates/2026-09-08 MARKDOWN-ENGINE - OPEN/update.md` for why this replaced
the app's original hand-rolled styler. `#`/`##`/`###` headers, `**bold**`,
`*italic*`, `` `code` ``, `> quotes`, `- [ ]` task lists, and `[text](url)`
`==highlight==`, and `~~strikethrough~~` links all render live as you type.
Cmd-B, Cmd-I, Cmd-Shift-H (highlight), Cmd-Shift-X (strikethrough), and
Cmd-E (inline code) wrap/unwrap the current selection, correctly toggling
between combinations (e.g. bold+italic → italic) instead of stacking. A
right-click also offers headings, lists, links, images, code blocks, and
horizontal rules — everything swift-markdown-engine's formatting actions
support, matching its own (unshipped) built-in menu.

When Page and Notes are shown together, a **link toggle** by the section
chips switches between scrolling the two panes together (linked, the default)
and scrolling each independently (unlinked). Selecting text in **Page** pops
up a **Comment** button: it drops the quoted passage into Notes as a
clickable chip followed by your comment, and clicking that chip jumps Page
back to the passage.

Notes support **timenotes** — lines that link back to a moment in the
lesson's video/audio: `> @timenote(at: SECONDS){[MM:SS]} your note text`,
rendered as a clickable `[MM:SS]`/`[HH:MM:SS]` pill (the same format as the
transcript) that seeks playback. Simply typing a bare `[MM:SS]` (or
`[H:MM:SS]`) in Notes also turns into a clickable pill automatically. Create a
full timenote by
clicking the comment-bubble button in the video transport bar (inserts a
timenote at the current position — no longer auto-focuses Notes, see the
update note above), or by typing `/timenote` and pressing Enter inside
Notes, Notion-style. `HH:MM:SS.mmm` (period-delimited milliseconds) is
deliberately the same clock the **Transcript** feature uses, so notes
and transcript cues line up on one timeline. Lesson notes
written with the older `> [!timenote HH:MM:SS.mmm] text` syntax upgrade
automatically the first time they're opened. Any Markdown file opened from
a ghost/attachment while editing gets the same live styling (minus
timenotes, which are Notes-specific).

### Transcript

If a lesson folder contains a Markdown file named like its media file
(`Lesson 1.mp4` → `Lesson 1.md`), it's treated as a **transcript** and a
**Transcript** chip appears in the content selector. It is read-only — an
imported artifact, never edited in-app — and is never mistaken for `page.md`
(the base-name match is excluded from the legacy single-Markdown → Page
migration; a `page.mp4`/`note.mp4` video keeps its authored `page.md`/`note.md`
rather than adopting it as a transcript).

The transcript is a conversation rendered as timestamped **cues**. Each cue is
a header line — a bold speaker name (color-coded per speaker), a `[MM:SS]`
(or `[H:MM:SS]`) timestamp,
and an optional annotation like `(interrupting)` — followed by the spoken
text:

```text
**Obchodník** [00:30]
Radku, zdravím vás!

**Klient** [09:51] (interrupting)
Uhu.
```

Clicking a cue's timestamp seeks the player to that moment. As playback
advances, the current cue is highlighted and the transcript follows along,
keeping it in view; scrolling by hand detaches the follow (a **Jump to
current** pill brings it back, as does clicking any timestamp). Because it
needs to stay beside the video while it scrolls and recenters, selecting the
Transcript switches the lesson's detail area to a pinned-video-on-top layout
(the other sections keep the normal single-scroll page). A transcript whose
media can't be played still reads fine — its timestamps are just inert.

This is a breaking format change from the original flat
`Lesson Name.mp4` + `Lesson Name.md` layout — classrooms in the old format
need to be manually restructured into lesson folders; there is no
automatic migration.

## Building

```sh
swift build
swift test
swift run ClassroomSmokeTests
swift run Classroom
```

To build the standalone `.app` launcher:

```sh
scripts/create-launcher-app.sh
```

## Project layout

- `Sources/ClassroomCore` — non-UI, testable core (models, services,
  view models).
- `Sources/ClassroomApp` — SwiftUI app and views.
- `Tests/` — unit and smoke tests.
- `docs/` — phase-by-phase scope and verification checklists.
- `updates/` — dated update folders tracking what shipped and why (see
  `CLAUDE.md` for the workflow).

## Working on this repo

See `CLAUDE.md` for the working principles and update-tracking workflow used
in this project.

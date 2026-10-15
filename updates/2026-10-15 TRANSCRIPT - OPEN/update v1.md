# Transcript tab

## Goal

Give a lesson an optional **transcript**: if a lesson folder contains a
markdown file named like the video (`call.mp4` → `call.md`), the app treats
it as a transcript and exposes a **Transcript** section (chip) alongside
Page / Notes — a peer in the existing 1-or-2-pane selector, shown only when
the sidecar file exists.

The transcript is a two-speaker conversation rendered as a scrolling list of
timestamped **cues**:

```
**Obchodník** [00:30]
Radku, zdravím vás!

**Klient** [09:51] (interrupting)
Uhu.
```

Required behaviors:

1. Click a cue's `[MM:SS]` timestamp → the video **seeks** to that moment.
2. As the video plays, the cue at the current time is **highlighted**.
3. When the Transcript section is on screen it **auto-follows** playback
   (keeps the active cue in view) and **recenters on open**, but the user can
   freely scroll; a genuine user scroll **detaches** follow until they tap
   "Jump to current" or seek.

## Decisions (confirmed with product owner, 2026-10-15)

- **Layout: stacked.** When Transcript is among the selected sections, the
  detail area switches from the single outer `ScrollView` to a **pinned
  video on top + a scrolling content region below**. Page/Notes-only
  selections keep today's behavior untouched.
- **Transcript is a normal peer section.** It uses the existing
  `LessonContentSection` chip model and `ContentSectionSelectionService`
  2-up split logic — so `Transcript ∥ Notes` (or `∥ Page`) is allowed, just
  like any other pairing. No special mutual-exclusivity.
- **Discovery by video base name.** The sidecar is the `.md` whose base name
  equals the media file's base name. It must be **excluded** from the
  scanner's "stray markdown → migrate to `page.md`" path so a transcript is
  never silently turned into the Page. `page.mp4`/`note.mp4` collisions:
  Page/Notes win, no transcript registered.
- **Speaker differentiation = quiet name color only** (accent for one speaker,
  `.primary` for the other). No bubbles, avatars, or alternating sides.
- **Shared clock.** Reuse the `TimenoteFormat` seconds convention and the
  existing click-to-seek pattern (`PlaybackService.seek`,
  `currentTimeSeconds`).

See `wiki.md` for durable design detail (cue styling, highlight values,
follow state machine, macOS-14 scroll constraints).

## Roadmap

Status: ☐ todo · ◐ in progress · ☑ done

### Phase 0 — Model & discovery (Core)  ☑
- [x] Add `Lesson.transcriptURL: URL?` (defaulted, so existing call sites
      are untouched).
- [x] `ClassroomScanner.scanLesson`: detect `<mediaBaseName>.md` as the
      transcript; pass it to `resolvePageAndNoteURLs` so it's excluded from
      page-migration / stray-markdown warnings.
- [x] `page.mp4`/`note.mp4` collision guard (Page/Notes take precedence).
- [x] Tests: `TranscriptScanningTests` — discovered; not migrated to page;
      collision guard; case-insensitive; no-transcript; coexists with
      page.md + note.md. 7 tests, green.

### Phase 1 — Parsing (Core)  ☑
- [x] `TranscriptCue` model (speaker→color mapping left to the view).
- [x] `TranscriptParser`: markdown → `[TranscriptCue]`. Header regex
      `**Speaker** [ts] (paren)?`; `[MM:SS]`, `[H:MM:SS]`, `[HH:MM:SS]`
      (+ optional fractional seconds); unparseable "headers" fold into the
      current cue's body; `end` = next cue's `start` (last = `.infinity`).
      Never throws.
- [x] `TranscriptService` (load + parse, mirror `NotesService`, read-only).
- [x] Active-cue resolution: `[TranscriptCue].activeCueID(at:)` binary search.
- [x] Tests: `TranscriptParserTests` — real examples, multi-paragraph cue,
      parentheticals, inline `[nesrozumitelné]`, H:MM:SS + fractional,
      preamble, non-header bold line, empty, active-cue lookup. 11 tests.

### Phase 2 — ViewModel & section availability  ☑
- [x] `LessonContentSection.transcript` + title.
- [x] Inject `TranscriptService`; `@Published transcriptCues` +
      `transcriptErrorMessage`; `loadTranscriptForSelectedLesson()` in the
      load flow; clear on lesson deselect.
- [x] `availableContentSections` so the Transcript chip renders only when a
      transcript exists; `LessonContentSectionSelector` honors it; stale
      `.transcript` selections pruned on lesson switch (never empty).
- [x] Tests: transcript smoke scenario in `main.swift` — discovery,
      availability, cue parse, active-cue lookup, toggle, prune-on-switch.
      (Temporary `Text("Transcript")` placeholder in the pane switch, replaced
      in Phase 3.)

Note: `swift test` has one PRE-EXISTING unrelated failure
(`SmokeTests.testAttachmentsOnlyExposedWhenNonEmpty`) — logged in
`issues.txt`. All transcript tests pass.

### Phase 3 — Cue rendering (TranscriptView, static)  ☑
- [x] `TranscriptCueRow` per the wiki spec (name color, timestamp pill
      rest/hover + pointing-hand cursor, parenthetical, body, same-speaker
      grouping, active-cue accent bar + tint with 0.18s cross-fade).
- [x] Click timestamp → `playbackService.seek`; active cue from
      `currentTimeSeconds` via `activeCueID(at:)`. Inert timestamps when no
      playable media (`canSeek`).
- [x] `case .transcript` → `TranscriptView` in the content-pane switch.

### Phase 4 — Pinned stacked layout  ☑
- [x] `ClassroomBrowserView.detail` branches: `isTranscriptMode` (transcript
      among selected) → `transcriptModeDetail` (header + video + selector
      pinned, `LessonContentPane` fills remaining height and scrolls); else
      `scrollingDetail` (the original single outer `ScrollView`, unchanged).
      Section switch extracted to `sectionView(_:)`. Paired Page/Notes panes
      wrapped in their own `ScrollView` within the bounded region.
      (Attachments are intentionally not shown in transcript mode — it's a
      focused reading layout; they remain in Page/Notes modes.)

### Phase 5 — Follow / auto-scroll / recenter  ☑
- [x] `ScrollViewReader` + `TranscriptFollowCoordinator`. Recenter on open
      (top if nothing played yet; upper-third otherwise), one runloop hop so
      the `LazyVStack` realizes the row. Fresh `.id(lesson)` re-centers on
      lesson switch.
- [x] Band via cue-index threshold (recenter only once the active cue is ≥3
      cues from the last centered one) — cheap stand-in for the geometry band,
      avoids per-tick scrolling.
- [x] Detach on genuine user scroll via `NSScrollView`
      `willStartLiveScroll`/`didLiveScroll` (found with `ScrollViewLocator`;
      guarded against our own programmatic scrolls).
- [x] "Jump to current" pill while detached (shown whenever detached with an
      active cue — the off-screen-only refinement needs row geometry; deferred
      as it would add a preference-key pass). Re-attach + optimistic recenter
      on click-to-seek and on the pill.

Needs real-app manual verification (the AppKit live-scroll bridge and
`scrollTo` centering can't be unit-tested) — see Phase 7.

### Phase 6 — Edge states & docs  ☑
- [x] Unparseable/empty transcript → chip still shows, quiet
      "This transcript couldn't be read." message (`transcriptErrorMessage`).
- [x] Transcript present but media unplayable → readable, timestamps inert
      (`canSeek == false`).
- [x] Malformed/non-header lines fold into the current cue (parser).
- [x] README updated (structure diagram, selector, new Transcript section,
      timenote clock note). `wiki.md` holds the durable design.

### Phase 7 — Verify & ship  ◐
- [x] `swift build`, `swift test` (one pre-existing unrelated failure — see
      `issues.txt`), `swift run ClassroomSmokeTests` (passes).
- [ ] Rebuild `Classroom.app` launcher via
      `scripts/create-launcher-app.sh`; user relaunches.
- [ ] Manual verification checklist (below).

## Manual verification checklist

Drop a `.md` named like a lesson's video into that lesson's folder, re-open
the classroom, select the lesson, then:

1. **Chip appears** only for lessons that have the transcript file; absent
   otherwise.
2. **Rendering** — speakers colored (first speaker accent, other primary),
   repeated same-speaker labels suppressed, `(interrupting)` muted-italic,
   timestamps right-aligned; readable in light *and* dark mode.
3. **Click-to-seek** — clicking a `[MM:SS]` jumps the video there; hovering a
   timestamp shows the pill + pointing-hand cursor.
4. **Live highlight** — playing the video highlights the current cue; the
   highlight advances as playback moves.
5. **Auto-follow** — the list keeps the active cue in view; opening the tab
   recenters on it (top if nothing has played yet).
6. **Detach + resume** — scrolling by hand stops the auto-follow; a
   "Jump to current" pill appears and (like clicking any timestamp) resumes
   it. *(This is the riskiest bit — the user-scroll detection rides on the
   AppKit live-scroll bridge; confirm a manual scroll actually detaches and a
   programmatic recenter does not.)*
7. **Layout** — with Transcript selected the video stays pinned on top while
   the transcript scrolls; Page/Notes selections are unchanged. Transcript ∥
   Notes split works.
8. **Lesson switch** — switching lessons with the tab open recenters on the
   new lesson's transcript; a lesson without one drops the chip and selection.

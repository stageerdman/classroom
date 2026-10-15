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

### Phase 5 — Follow / auto-scroll / recenter  ◐
- [ ] `ScrollViewReader` + comfort-band (middle 60%) recenter; recenter on
      open (top if nothing played yet).
- [ ] Detach on genuine user scroll via AppKit `NSScrollView`
      `willStartLiveScroll`/`didLiveScroll` (macOS 14 — no `ScrollPhase`).
- [ ] "Jump to current" pill: only while detached AND active cue off-screen.
- [ ] Re-attach on any seek (incl. click-to-seek), optimistic recenter on the
      clicked cue.

### Phase 6 — Edge states & docs  ☐
- [ ] Unparseable/empty transcript → chip still shows, quiet message.
- [ ] Transcript present but video missing → readable, timestamps inert.
- [ ] README + `docs/` note; fill `wiki.md` lessons.

### Phase 7 — Verify & ship  ☐
- [ ] `swift build`, `swift test`, `swift run ClassroomSmokeTests`.
- [ ] Rebuild `Classroom.app` launcher; ask user to relaunch and run the
      manual verification checklist.

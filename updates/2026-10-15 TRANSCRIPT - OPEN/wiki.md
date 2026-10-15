# Transcript — durable design notes

Source: three parallel UX design passes (layout, cue reading experience,
follow/scroll interaction) + a code map of the existing player/tab/scanner
code, 2026-10-15.

## Why this fits the app with little risk

The app already shipped the hard parts: `PlaybackService.currentTimeSeconds`
(published ~2×/sec via a periodic observer) and `seek(to:)`, and a working
click-a-timestamp-to-seek pattern (the "timenote" pills in Notes). The
`TimenoteFormat` header comment even says transcripts should share its clock.
So the transcript is mostly *new UI over existing plumbing* plus pure parsing.

## Discovery (scanner)

A transcript sidecar = the `.md` in a lesson folder whose **base name equals
the media file's base name**. This is the first base-name sidecar in the app
(Page/Notes are matched by fixed filename). Critical: `resolvePageAndNoteURLs`
currently treats any non-`page.md`/`note.md` markdown as a legacy page
candidate and will migrate the alphabetically-first one into `page.md`. The
transcript file MUST be excluded from that set. Collision guard: if the video
is literally `page.mp4`/`note.mp4`, Page/Notes win and no transcript is
registered.

## Cue model

```swift
struct TranscriptCue: Identifiable {
    let id: Int          // == index in the sorted array
    let start: Double    // seconds
    let end: Double      // next cue's start, or .infinity for the last
    let speaker: String  // raw name as authored ("Obchodník")
    let parenthetical: String?   // "(interrupting)" on the header row
    let text: String     // body, may be multiple paragraphs
}
```

Active cue = **last cue whose `start ≤ currentTime`** (binary search); `nil`
only when `t < cues.first.start`. Active cue is a pure function of
`currentTimeSeconds`, so scrub / skip / resume all flow through one path.

Parse rules: header line matches `**Name** [ts] (paren)?`; timestamps accept
`[MM:SS]`, `[H:MM:SS]`, `[HH:MM:SS]`. Lines that don't match a header fold
into the current cue's body (blank lines preserved as paragraph breaks). Never
throws — malformed input degrades to best-effort cues; stray text before the
first header becomes a preamble cue (or is dropped — decide in Phase 1).

## Cue reading experience (visual spec)

One calm left-aligned reading column (play-script, not chat):

- **Header row:** speaker name (left) + optional `(paren)` + `Spacer()` +
  timestamp (right, same baseline). Body paragraph below at the same left
  margin (no indent).
- **Speaker color:** Obchodník → `controlAccentColor`; Klient → `.primary`;
  any other/unknown name → `.primary`. Color lives ONLY on the name token;
  body is always `.primary`.
- **Same-speaker grouping:** when the next cue is the same speaker, suppress
  the name but keep the timestamp; use the tighter vertical gap.
- **Timestamp affordance:** at rest, bare accent mono-digit text
  (`monospacedDigit`, 11pt semibold, `controlAccentColor`, brackets at 0.5
  alpha). On hover, the familiar notes pill materializes (accent @ 0.15 bg,
  radius 5, pointing-hand cursor). Mono digits keep the right edge aligned.
- **Active-cue highlight:** 3pt accent left-bar (full opacity) + background
  tint `controlAccentColor` @ 0.08 light / 0.12 dark, radius 6, 8pt padding.
  Cross-fade `.easeInOut(0.18s)` on active-cue change. No body reflow/bolding.
- **Type scale:** name 13 semibold; timestamp 11 semibold mono; parenthetical
  12 regular italic `.secondary`; body 15 regular `.primary`, line-spacing +4
  (matches Notes, gives Czech diacritics headroom).
- **Density:** 20pt gap between speaker changes, 8pt between same-speaker
  cues, 3pt name→body, 16pt side insets, max text measure ~640pt.
- **Parentheticals:** `(interrupting)` on the header row (muted italic);
  inline `[nesrozumitelné]` stays in the body but drops to `.secondary`.

## Follow / auto-scroll / recenter

State machine: **FOLLOWING** (default) ↔ **DETACHED**.

- FOLLOWING → DETACHED on a genuine user scroll gesture (NOT on offset deltas,
  which would make auto-scroll detach itself).
- DETACHED → FOLLOWING only on explicit intent: tap "Jump to current", or any
  seek (scrubber drag-end, skip, resume, **click-to-seek on a cue**). Never
  auto re-attach just because the active cue scrolled back into view.
- Recenter-on-open: on appear, `isFollowing = true`, scroll active cue to
  center **without animation**; rest at **top** if nothing has played yet
  (active cue is first/`nil`). Defer one runloop hop so `LazyVStack` realizes
  the target row before `scrollTo`.
- Comfort band: while FOLLOWING, only recenter when the active cue leaves the
  **middle 60%** of the viewport (dead zones top/bottom 20%); then animate
  `.easeInOut(0.35s)`. Avoids per-tick jitter.
- "Jump to current" pill: visible only while DETACHED **and** the active cue
  is off-screen; bottom-center, `.regularMaterial`, arrow indicates direction.

### macOS 14 constraint (IMPORTANT)

Deployment target is `.macOS(.v14)`. `onScrollPhaseChange` /
`onScrollGeometryChange` are **macOS 15+** and cannot be used. Detect
user-vs-programmatic scroll via the underlying `NSScrollView`:

- `NSScrollView.willStartLiveScrollNotification` / `didLiveScrollNotification`
  fire for trackpad/wheel input but **not** for programmatic
  `NSClipView.scroll(to:)` / animator moves — the AppKit equivalent of a user
  gesture. Discover the `NSScrollView` behind the SwiftUI `ScrollView` with a
  tiny `NSViewRepresentable` probe.
- Belt-and-suspenders: wrap programmatic scrolls in an
  `isProgrammaticallyScrolling` flag and ignore live-scroll notifications
  while it's set (cleared next runloop tick).
- `scrollTo` has no completion callback — never gate logic on an assumed
  animation duration.

Simpler first-cut option for the band test: track active-cue **index** vs
last-centered index and recenter when they differ by ≥ K (K ≈ rows in ~40% of
the viewport). Upgrade to measured row frames if long cues make it feel loose.

## Layout

Peer section + stacked pinned layout. When `selectedContentSections` contains
`.transcript`: render header + chips + video pinned at the top (not scrolling),
then `LessonContentPane` filling the remaining height in its own scroll region.
`LessonContentPane` already does the 1-or-2 column split, so `Transcript ∥
Notes` reuses it. Non-transcript selections keep the existing single outer
`ScrollView` exactly as-is.

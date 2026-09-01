# Video Improvements

## Goal

Bring the lesson video player up to the level of a modern video app: real
full-screen playback, quick 15-second skip controls, and a YouTube-style
scrub preview (timestamp + thumbnail) when hovering the progress line.

## Why

The player today (`Sources/ClassroomApp/Views/PlayerView.swift`) is a thin
`NSViewRepresentable` wrapper around AVKit's `AVPlayerView` with
`controlsStyle = .floating`, embedded at a fixed 360pt height inside the
lesson card (`ClassroomBrowserView.swift`, `mediaPlayer`). That gets
play/pause, volume, and a bare scrubber for free, but:

- Full-screen relies entirely on whatever AVPlayerView's floating chrome
  does inside a fixed-height, clipped, rounded-rect container — not
  confirmed to behave like a real full-screen video experience.
- There's no 15-second skip forward/back — AVPlayerView doesn't expose
  this by default.
- There's no scrub-bar hover preview (timestamp or thumbnail) — AVKit's
  built-in scrubber doesn't support this on macOS.

`PlaybackService` (`Sources/ClassroomCore/Services/PlaybackService.swift`)
already tracks `currentTimeSeconds`, `durationSeconds`, and exposes
`seek(to:)`, which is most of what custom transport controls need.

## Scope

1. **Full-screen video**
   - Verify what AVPlayerView's native full-screen affordance currently
     does in our layout; if it's broken/absent, replace it with an
     explicit full-screen presentation (dedicated full-screen `NSWindow`
     or SwiftUI's window full-screen support) triggered by a control we
     own, so behavior isn't at the mercy of AVKit chrome.
   - Keep playback state (time, rate) continuous across the
     windowed ↔ full-screen transition.

2. **Skip ±15s**
   - Add back/forward 15s buttons to the transport controls.
   - Wire to `PlaybackService.seek(to:)` (clamped to `[0, duration]`).
   - Standard keyboard shortcuts (e.g. Left/Right arrow) as a stretch goal.

3. **Scrub-bar hover preview**
   - On hover over the progress line, show the timestamp under the cursor
     immediately (cheap: derived from hover position × duration).
   - Also show a small thumbnail frame at that timestamp, YouTube-style.
     Thumbnails need to be generated from the video asset
     (`AVAssetImageGenerator`), which is the meaty part of this item:
     - Generate on demand vs. pre-generate a sparse thumbnail sprite when
       a lesson loads (pre-generation avoids hitching on every hover but
       costs time/disk on load).
     - Cache thumbnails per lesson (keyed by file + mtime) so re-opening a
       lesson doesn't regenerate them — likely lives under the existing
       `.classroom/` metadata directory, or a `Caches/`-style subfolder so
       it isn't confused with user data. **Follow-up decision needed**
       once we're actually implementing this, ideally before writing
       cache files to disk.

Given (1) and (3) both push against what AVPlayerView's built-in chrome
can do, the likely shared direction is: drop `controlsStyle` down to
`.none` (bare video surface) and build our own SwiftUI transport bar
(play/pause, skip ±15s, scrubber with hover preview, full-screen toggle)
on top of `PlaybackService`. That's a bigger lift than three independent
small features, but it avoids fighting AVKit's chrome three separate times
and gives consistent behavior across all three asks. Worth confirming
before starting.

## Open questions (to resolve before/at implementation start)

- Custom transport bar (own play/pause/volume/etc. — bigger lift, full
  control) vs. layering only the missing pieces (skip buttons + hover
  preview) on top of the existing AVPlayerView chrome, if that turns out
  to be feasible?
- Thumbnail preview: pre-generate a sprite sheet on lesson load, or
  generate on demand per hover with a small debounce/cache? Where do
  cached thumbnails live on disk?
- Full-screen: real macOS full-screen window (green-button style) or an
  in-app "theater mode" (video fills the app window without a system
  full-screen transition)?

## Verification (once implemented)

- `swift build`, `swift test`, `swift run ClassroomSmokeTests`.
- Manual: open a lesson video, confirm skip ±15s clamps correctly at the
  start/end of the video; confirm full-screen entry/exit preserves
  playback position and rate; confirm scrub hover shows the correct
  timestamp and a thumbnail that matches that point in the video, for
  both a freshly-opened lesson and a re-opened one (cache reuse).

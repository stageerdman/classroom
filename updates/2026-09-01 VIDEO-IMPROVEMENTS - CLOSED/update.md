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
can do, the shared direction taken: drop `controlsStyle` down to `.none`
(bare video surface) and build our own SwiftUI transport bar (play/pause,
skip ±15s, scrubber with hover preview, mute, full-screen toggle) on top
of `PlaybackService`. Bigger lift than three independent small features,
but avoids fighting AVKit's chrome three separate times and gives
consistent behavior across all three asks.

## Decisions (resolved)

- Custom transport bar, not layered on native AVKit chrome.
- Thumbnails pre-generated on lesson load (not per-hover), cached to disk
  under `.classroom/thumbnails/<lesson>/`, keyed by source file size +
  mtime so an edited/replaced video regenerates instead of showing stale
  frames.
- Full-screen is a real macOS full-screen window (system green-button
  transition), not an in-app theater mode — a dedicated `NSWindow` popped
  out from the main window, so the sidebar/notes/attachments stay put
  underneath rather than being hidden.

## What shipped

- `PlaybackService` (`Sources/ClassroomCore/Services/PlaybackService.swift`):
  `isPlaying`/`isMuted`/`isAudioOnly` state, `togglePlayPause()`,
  `skipForward()`/`skipBackward()` (±15s, clamped to `[0, duration]`),
  `toggleMute()`.
- `ThumbnailService` + `ScrubThumbnailProvider` (`ClassroomCore/Services`,
  `ClassroomCore/ViewModels`): generates a sparse, disk-cached set of
  scrub thumbnails per lesson via `AVAssetImageGenerator`, published
  progressively so hovering works as soon as frames exist.
- `VideoTransportControlsView` + `ScrubberView` + `ScrubPreviewPopover`
  (`ClassroomApp/Views`): the custom transport bar — play/pause, ±15s
  skip (also bound to Left/Right arrow keys, Space for play/pause),
  scrubber with hover timestamp + thumbnail, mute, full-screen.
- `FullScreenPlayerWindowController` (`ClassroomApp/FullScreen`): pops
  playback into its own real full-screen window; Escape, the system
  green button, or the transport bar's own full-screen button all exit
  the same way.
- **Audio-only lessons** (`.mp3`/`.m4a`/`.wav`): no video surface, no
  thumbnail generation, no full-screen button — just the transport bar
  (play/pause, skip ±15s, scrubber, mute) sitting directly in the lesson
  pane using normal system control colors instead of the white-on-black
  video-overlay styling.
- Removed the old static "Saved position" `ProgressView` — the transport
  bar's live current/duration display made it redundant.
- **Pop-out player** (`ClassroomApp/Popout/PopoutPlayerWindowController.swift`):
  a "pip.enter" button next to full-screen detaches video playback into
  an ordinary, resizable, always-on-top (`.floating` window level)
  window the user can drag anywhere — distinct from full-screen, which
  is a system full-screen space. While popped out, the embedded lesson
  pane shows a "Playing in a floating window" placeholder with a
  "Bring Back" button instead of a second copy of the video. Switching
  lessons (or the popout's own close button) closes it automatically, so
  a stale `AVPlayer` never lingers in a floating window.

## Backlog

A CapCut-style timeline scrubber (filmstrip instead of a plain line,
zoom/pan, waveform for audio) was discussed and deliberately deferred —
see `updates/2026-09-01 TIMELINE-SCRUBBER - BACKLOG/update.md`.

## Verification

- `swift build`, `swift test`, `swift run ClassroomSmokeTests` all pass
  (one pre-existing, unrelated `SmokeTests` failure predates this update
  — confirmed present on `master` before this work too).
- Added `ThumbnailServiceTests` covering `sampleTimes` spacing/bounds.
- Manual (in-app, by the user): confirmed the transport bar renders and
  the ±15s skip / scrubber / time labels work against a real lesson
  video, including the audio-only bar. Full-screen and pop-out
  confirmed working manually by the user (2026-09-02) — closing.

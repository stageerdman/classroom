# Playback Speed

## Goal

Let the user speed up video/audio playback from a button on the transport
bar: click it, drag a slider from 1x to 3x in 0.25x steps. Speedup only —
no slow-motion — per the ask.

## Why

`PlaybackService` already had `playbackRate`/`setPlaybackRate(_:)` wired
into `play()`, but nothing in the UI ever called it — there was no way to
change speed from the app.

## What shipped

- `PlaybackService` (`Sources/ClassroomCore/Services/PlaybackService.swift`):
  `setPlaybackRate(_:)` now clamps to `[minPlaybackRate, maxPlaybackRate]`
  (1x–3x) and snaps to the nearest `playbackRateStep` (0.25), replacing
  the old fixed-list-of-rates check (which also allowed 0.5x slow-motion,
  no longer wanted).
- `PlaybackSpeedControlView` (`Sources/ClassroomApp/Views/PlaybackSpeedControlView.swift`):
  new button showing the current speed (e.g. "1.5x") that opens a
  popover with a `Slider` bound to `playbackService.playbackRate`,
  ranging 1x–3x in 0.25 steps.
- Wired into `VideoTransportControlsView`, next to the mute button — so
  it shows up everywhere that transport bar is used: the lesson pane,
  full-screen window, and pop-out window (video and audio-only lessons
  alike).

## Verification

- `swift build`, `swift test`, `swift run ClassroomSmokeTests` — smoke
  tests pass, including new coverage for clamping above 3x, clamping
  below 1x, and snapping to the nearest 0.25 step. One pre-existing,
  unrelated `SmokeTests` failure (`testAttachmentsOnlyExposedWhenNonEmpty`,
  a test-ordering bug writing a file before its parent directory exists)
  predates this change.
- Manual verification (by the user): open a lesson, click the speed
  button in the transport bar, drag the slider, confirm playback speed
  changes and the label updates.

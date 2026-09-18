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
  changes and the label updates — confirmed working (2026-09-08).

## Follow-up fix (2026-09-14): doubled/echoed audio above 1x

Reported symptom: at speeds above 1x, the voice sometimes sounded
doubled after resuming from a pause; skipping forward/backward 15s
cleared it until the next pause/resume.

Root cause: `PlaybackService.play()`
(`Sources/ClassroomCore/Services/PlaybackService.swift`) resumed via
`player.playImmediately(atRate:)`, which is meant for pre-primed,
low-latency resume (e.g. live streams) and can start decoding before
the render pipeline has settled — worse at higher rates, since more
audio has to be decoded per second immediately. `togglePlayPause()`
and `scrubEnded()` both call `play()` on every resume, which is why it
recurred after every pause; a bare `seek()` (used by skip
forward/back) forces AVFoundation to flush and rebuild the render
pipeline, which is why seeking cleared it.

Fix: `play()` now resumes by setting `player.rate` directly instead of
`playImmediately(atRate:)` — AVFoundation's standard resume-at-speed
path, with no pre-priming assumption.

Verification: `swift build`, `swift test` (same pre-existing
`testAttachmentsOnlyExposedWhenNonEmpty` failure, unrelated),
`swift run ClassroomSmokeTests` all pass. Manual verification pending
— user to confirm doubled audio no longer occurs at 2x+ after
pausing/resuming.

## Follow-up fix (2026-09-18): doubling persisted after the rate-only fix

Reported symptom, unchanged from the 09-14 report: at speeds above 1x
the voice sounds doubled, and it only sounds normal right after
seeking (clicking the track or skipping 15s) — so the 09-14 fix
(setting `player.rate` directly in `play()` instead of
`playImmediately(atRate:)`) did not actually resolve it.

Root cause (refined): setting `rate` alone on a *paused* player isn't
enough to avoid the doubling — AVFoundation's time-pitch render
pipeline can still be holding a stale, already-buffered chunk of audio
from before the pause. When `rate` flips the player back to playing,
that stale chunk gets flushed out alongside freshly decoded audio,
producing the doubled/echoed sound. A `seek()` avoids this because
seeking forces AVFoundation to flush and rebuild the render pipeline
from scratch — which is why scrubbing or skipping always cleared it.

Fix: `play()` now performs a zero-tolerance no-op seek to the current
position *before* setting `rate`, whenever resuming above 1x — forcing
the same pipeline flush a manual scrub would, without perceptibly
moving playback. At 1x, `rate` is set directly as before (no pipeline
staleness to worry about since there's no time-pitch processing).

Verification: `swift build`, `swift test`, `swift run
ClassroomSmokeTests` pending Xcode license acceptance on this machine
(`sudo xcodebuild -license`, blocked on running commands as `sudo`).
Manual verification pending — user to confirm doubled audio no longer
occurs at 2x+ after pausing/resuming.

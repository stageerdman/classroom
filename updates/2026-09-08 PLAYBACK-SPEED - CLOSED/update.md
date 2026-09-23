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
ClassroomSmokeTests` all pass (same pre-existing, unrelated
`testAttachmentsOnlyExposedWhenNonEmpty` failure). Manual
verification (by the user): the resume-from-pause doubling was fixed,
but a persistent echo/phasing remained during continuous playback,
worsening over time — see the 09-18 follow-up below, a distinct root
cause from the same symptom family.

## Follow-up fix (2026-09-18): persistent echo during playback, not just on resume

Reported symptom, after the seek-flush fix above resolved the
resume-from-pause doubling: audio at 2x+ still sounded like an echo —
"two tracks playing" — continuously during playback, and the effect
got worse the longer it played, not just right after a pause/resume.

Root cause: unrelated to the resume path. `PlaybackService.load(url:)`
never set `AVPlayerItem.audioTimePitchAlgorithm`, so AVFoundation used
its default algorithm (`.spectral`), which is tuned for preserving
music's harmonic content, not speech. On spoken-word audio, `.spectral`
processing is prone to a phasey, echo-like artifact that compounds
over the course of playback as the phase-vocoder's window alignment
drifts — matching both "sounds like two tracks" and "gets worse after
a while."

Fix: `load(url:)` now sets `item.audioTimePitchAlgorithm = .timeDomain`
on every loaded item — the algorithm Apple recommends for spoken-word
content, cheaper and without the phasing artifact.

Verification: `swift build`, `swift test`, `swift run
ClassroomSmokeTests` all pass (same pre-existing, unrelated failure).
Manual verification pending — user to confirm the echo is gone at 2x+,
including over extended playback.

## Follow-up fix (2026-09-23): the doubling was multiple audio tracks, not time-pitch

Reported symptom, still present after every fix above: at fast speed the
voice sounds doubled; it syncs momentarily then clicks. The user
narrowed it to a specific kind of file — their own `.mov` screen/call
recordings, e.g. `Sales Call - Miroslav.mov`.

Root cause (the real one): those recordings are made with **OBS**, which
writes **several audio tracks** into one file — a master mix plus one
track per source (microphone, desktop audio). `ffprobe` on the reported
file showed three stereo AAC audio tracks; track 1 was the loudest
(−20.5 dB vs −23.1 / −22.7), the signature of the master mix sitting
alongside its own component sources. AVPlayer plays *every* enabled
audio track at once, so the mix stacked on top of the sources it already
contained — literally two-to-three copies of the same voice. Barely
audible at 1x; glaring above 1x, where each track is independently
time-stretched, the copies drift apart, then periodically click back
into sync. A seek cleared it only because it momentarily realigned all
the tracks. Every prior fix (`playImmediately` → `rate`, seek-flush,
`.spectral` → `.timeDomain`) was aimed at the time-pitch pipeline, which
was never the cause — hence none of them held.

Fix: `PlaybackService` now isolates a single audio track. When a player
item reaches `.readyToPlay`, `isolateFirstAudioTrack(on:)` disables all
but the first audio track (lowest `trackID` = OBS track 1, the full
mix), so the complete audio plays exactly once. Single-track files are
untouched. The `.timeDomain` algorithm and the resume seek-flush are
left in place — both remain correct — but with one audio stream the
doubling has no source at any speed.

Verification: `swift build`, `swift test`, `swift run
ClassroomSmokeTests` all pass (same pre-existing, unrelated
`testAttachmentsOnlyExposedWhenNonEmpty` failure). Launcher rebuilt via
`scripts/create-launcher-app.sh`. Manual verification pending — user to
relaunch and confirm the doubling is gone at 2x on the OBS `.mov`
recordings.

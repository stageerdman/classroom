# Phase 4 Checklist

## Scope

- Local video playback surface
- Play and pause controls
- Seek forward and backward controls
- Playback speed control
- Previous and next lesson commands
- Safe missing-file playback errors

## Automated Verification

- `swift test`
- `swift run LocalClassroomSmokeTests`
- `swift build`

## Manual Verification

- Run `swift run LocalClassroom`.
- Open a classroom containing MP4, MOV, and M4V samples.
- Select a lesson and play it.
- Seek with the player and toolbar controls.
- Change playback speed.
- Use previous and next lesson buttons.
- Enter full screen from the native video controls.
- Remove a selected video in Finder, refresh, and verify the app recovers without crashing.

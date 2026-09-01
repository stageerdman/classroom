# Timeline Scrubber (CapCut-style)

**Status:** Backlog — not started, not scheduled. Captured so the idea
isn't lost, not an active update. (Deviates from the usual OPEN/CLOSED
folder-status convention in `CLAUDE.md` on purpose — this isn't being
worked on, so marking it OPEN would misrepresent that and would also
violate the "only one OPEN update at a time" rule while
`2026-09-01 VIDEO-IMPROVEMENTS` is still open.)

## Idea

Rework the scrubber to look and feel like a video editor's timeline
(CapCut, Premiere, etc.) instead of the current simple progress line:

- Move the scrub/transport row to sit **below** the video frame instead
  of overlaid on top of it (so the mouse hovering the timeline doesn't
  cover the video itself).
- Replace the plain progress line with an actual **filmstrip** — visible
  thumbnail frames tiled along the timeline, not just a hover-triggered
  popover.
- Support **zooming in/out** on the timeline to see a narrower or wider
  time range in more or less detail, with panning once zoomed in.
- For **audio** lessons, show a **waveform/volume curve** in place of the
  filmstrip.
- Keep play/pause, ±15s skip, mute, and full-screen exactly as they are
  now.

## Why this is a bigger lift than it looks

Discussed with the user before deferring — three genuinely hard parts:

1. **Filmstrip density.** The current `ThumbnailService` generates a
   sparse set of frames (~10s apart, capped at 60) sized for a single
   hover popover. A continuous filmstrip needs far more frames — either
   generate densely upfront (slower lesson-open, more disk) or
   generate progressively as the visible/zoomed range changes (more
   moving parts, but scales better).
2. **Zoom/pan.** A real timeline widget with its own visible-range state
   (separate from total duration), gesture handling for zoom and pan,
   and reconciling that with seeking — this is the fiddliest part to get
   feeling right, and where most of the implementation time would go.
3. **Waveform generation.** New capability, not an extension of anything
   that exists — decoding audio samples (`AVAssetReader`) and downsampling
   to a cached amplitude envelope, analogous to how thumbnails are cached
   today but a different pipeline entirely.

## Suggested phasing (whenever this gets picked up)

1. Move the transport row below the video; swap the plain line for a
   filmstrip/waveform at a single fixed zoom level (no zoom/pan yet).
2. Add zoom/pan once the filmstrip/waveform itself looks and feels right
   at fixed zoom.

## Relevant existing code

- `Sources/ClassroomApp/Views/ScrubberView.swift`,
  `VideoTransportControlsView.swift` — current scrubber/transport bar to
  be reworked or replaced.
- `Sources/ClassroomCore/Services/ThumbnailService.swift`,
  `ViewModels/ScrubThumbnailProvider.swift` — current sparse thumbnail
  generation/caching; the filmstrip needs a denser sibling or a rework
  of this.

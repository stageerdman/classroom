import AppKit
import ClassroomCore
import SwiftUI

/// A lesson's transcript: a scrolling list of timestamped cues. Clicking a
/// cue's timestamp seeks the player; the cue at the current playback time is
/// highlighted. Auto-follow/recenter is layered on in a later phase — this
/// renders the list and the live highlight.
struct TranscriptView: View {
    let cues: [TranscriptCue]
    @ObservedObject var playbackService: PlaybackService
    /// A content-level problem (file present but unreadable/empty). Shown in
    /// place of the list.
    let errorMessage: String?

    /// First distinct speaker → accent, the rest → primary. A quiet, two-tone
    /// "who's talking" signal that doesn't try to scale a palette to N voices.
    private let speakerColors: [String: Color]

    init(cues: [TranscriptCue], playbackService: PlaybackService, errorMessage: String?) {
        self.cues = cues
        self.playbackService = playbackService
        self.errorMessage = errorMessage
        self.speakerColors = Self.makeSpeakerColors(from: cues)
    }

    /// Only seek when there's actually something to seek — a transcript with
    /// no (or unplayable) media reads fine, but its timestamps are inert.
    private var canSeek: Bool {
        playbackService.player != nil
    }

    private var activeCueID: Int? {
        cues.activeCueID(at: playbackService.currentTimeSeconds)
    }

    var body: some View {
        Group {
            if let errorMessage {
                message(errorMessage)
            } else if cues.isEmpty {
                message("This lesson has no transcript.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(cues.enumerated()), id: \.element.id) { index, cue in
                            TranscriptCueRow(
                                cue: cue,
                                showsSpeaker: index == 0 || cues[index - 1].speaker != cue.speaker,
                                isFirst: index == 0,
                                isActive: cue.id == activeCueID,
                                speakerColor: speakerColors[cue.speaker] ?? .primary,
                                canSeek: canSeek,
                                onSeek: { playbackService.seek(to: cue.startSeconds) }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                }
                .animation(.easeInOut(duration: 0.18), value: activeCueID)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    private static func makeSpeakerColors(from cues: [TranscriptCue]) -> [String: Color] {
        var colors: [String: Color] = [:]
        for cue in cues where colors[cue.speaker] == nil {
            colors[cue.speaker] = colors.isEmpty ? .accentColor : .primary
        }
        return colors
    }
}

/// One transcript cue: a header row (speaker + optional annotation + a
/// clickable timestamp) over the spoken text. The active cue gets a calm
/// accent bar + tint.
private struct TranscriptCueRow: View {
    let cue: TranscriptCue
    /// Suppressed for a run of cues from the same speaker so the turn reads as
    /// one block; the timestamp still shows (each cue is its own seek target).
    let showsSpeaker: Bool
    let isFirst: Bool
    let isActive: Bool
    let speakerColor: Color
    let canSeek: Bool
    let onSeek: () -> Void

    /// Tighter rhythm within a speaker's turn, a clear beat between turns.
    private var topPadding: CGFloat {
        if isFirst { return 0 }
        return showsSpeaker ? 20 : 8
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if showsSpeaker {
                    Text(cue.speaker)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(speakerColor)
                }
                if let parenthetical = cue.parenthetical {
                    Text(parenthetical)
                        .font(.system(size: 12).italic())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                TranscriptTimestampButton(seconds: cue.startSeconds, canSeek: canSeek, onSeek: onSeek)
            }

            Text(cue.text)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .lineSpacing(4)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 640, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(
            isActive ? Color.accentColor.opacity(activeTintOpacity) : .clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .overlay(alignment: .leading) {
            if isActive {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 4)
            }
        }
        .padding(.top, topPadding)
    }

    /// A touch more tint in dark mode — the same accent reads weaker against a
    /// dark field.
    @Environment(\.colorScheme) private var colorScheme
    private var activeTintOpacity: Double {
        colorScheme == .dark ? 0.12 : 0.08
    }
}

/// The clickable `[MM:SS]` timestamp. Bare accent mono-digits at rest; a
/// filled pill + pointing-hand cursor on hover, so it only reads as a button
/// when the pointer is on it (there are hundreds of these).
private struct TranscriptTimestampButton: View {
    let seconds: Double
    let canSeek: Bool
    let onSeek: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSeek) {
            Text(Self.label(for: seconds))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(canSeek ? Color.accentColor : Color.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    (canSeek && isHovered) ? Color.accentColor.opacity(0.15) : .clear,
                    in: RoundedRectangle(cornerRadius: 5)
                )
        }
        .buttonStyle(.plain)
        .disabled(!canSeek)
        .onHover { hovering in
            isHovered = hovering
            guard canSeek else { return }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    /// `MM:SS` (minutes zero-padded so the mono-digit column stays aligned),
    /// `H:MM:SS` past an hour. Wrapped in brackets to match the source style.
    static func label(for seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "[%d:%02d:%02d]", hours, minutes, secs)
        }
        return String(format: "[%02d:%02d]", minutes, secs)
    }
}

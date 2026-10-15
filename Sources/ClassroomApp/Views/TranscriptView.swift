import AppKit
import ClassroomCore
import SwiftUI

/// A lesson's transcript: a scrolling list of timestamped cues. Clicking a
/// cue's timestamp seeks the player; the cue at the current playback time is
/// highlighted; while "following" the list keeps the active cue in view and
/// recenters when the tab opens. A real user scroll detaches follow until the
/// user taps "Jump to current" or clicks a timestamp. See
/// `TranscriptFollowCoordinator` for the follow state and the macOS-14
/// user-scroll detection.
struct TranscriptView: View {
    let cues: [TranscriptCue]
    @ObservedObject var playbackService: PlaybackService
    /// A content-level problem (file present but unreadable/empty). Shown in
    /// place of the list.
    let errorMessage: String?

    @StateObject private var follow = TranscriptFollowCoordinator()

    /// Each distinct speaker gets its own color from `speakerPalette`, so a
    /// glance down the left margin tells turns apart by who's talking.
    private let speakerColors: [String: Color]

    /// A small, deliberate palette (system colors — legible as label tints in
    /// both light and dark mode). Assigned in order of first appearance, so
    /// the two main speakers get the two most-distinct leading hues; wraps
    /// around for transcripts with many names.
    private static let speakerPalette: [Color] = [
        .blue, .pink, .teal, .orange, .purple, .green, .indigo, .brown
    ]

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

    /// Show `HH:MM:SS` for every cue once the video (or the transcript's own
    /// span, if the duration isn't known yet) runs an hour or longer, so the
    /// timestamp column uses one consistent format throughout — otherwise
    /// `MM:SS`.
    private var usesHours: Bool {
        let span = max(playbackService.durationSeconds ?? 0, cues.last?.startSeconds ?? 0)
        return span >= 3600
    }

    var body: some View {
        Group {
            if let errorMessage {
                message(errorMessage)
            } else if cues.isEmpty {
                message("This lesson has no transcript.")
            } else {
                transcriptList
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var transcriptList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(cues.enumerated()), id: \.element.id) { index, cue in
                        TranscriptCueRow(
                            cue: cue,
                            showsSpeaker: index == 0 || cues[index - 1].speaker != cue.speaker,
                            isFirst: index == 0,
                            isActive: cue.id == activeCueID,
                            speakerColor: speakerColors[cue.speaker] ?? .primary,
                            usesHours: usesHours,
                            canSeek: canSeek,
                            onSeek: { seek(to: cue, proxy: proxy) }
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .background(ScrollViewLocator { follow.attach(to: $0) })
            }
            .animation(.easeInOut(duration: 0.18), value: activeCueID)
            .overlay(alignment: .bottom) { jumpToCurrentPill(proxy: proxy) }
            .animation(.easeInOut(duration: 0.2), value: follow.isFollowing)
            .onAppear {
                follow.reattachToActiveCue()
                // One runloop hop so the LazyVStack realizes the target row
                // before scrolling to it on first paint.
                DispatchQueue.main.async { recenter(animated: false, proxy: proxy) }
            }
            .onChange(of: activeCueID) { _, newID in
                guard follow.isFollowing, let newID, follow.shouldRecenter(forActiveCueID: newID) else {
                    return
                }
                recenter(animated: true, proxy: proxy)
            }
            .onDisappear { follow.detach() }
        }
    }

    @ViewBuilder
    private func jumpToCurrentPill(proxy: ScrollViewProxy) -> some View {
        if !follow.isFollowing, activeCueID != nil {
            Button {
                follow.reattachToActiveCue()
                recenter(animated: true, proxy: proxy)
            } label: {
                Label("Jump to current", systemImage: "scope")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 12)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    /// Click-to-seek: an explicit "take me here" intent, so it re-attaches
    /// follow and recenters optimistically on the clicked cue (the active-cue
    /// highlight catches up on the next time tick ~0.5s later).
    private func seek(to cue: TranscriptCue, proxy: ScrollViewProxy) {
        playbackService.seek(to: cue.startSeconds, precise: true)
        follow.reattachToActiveCue()
        scroll(to: cue.id, anchor: .center, animated: true, proxy: proxy)
        follow.lastCenteredCueID = cue.id
    }

    /// Scrolls the active cue into its resting position: the top for the very
    /// first cue (or before anything has played — no dead space above), the
    /// upper third otherwise.
    private func recenter(animated: Bool, proxy: ScrollViewProxy) {
        guard let firstID = cues.first?.id else {
            return
        }
        let target = activeCueID ?? firstID
        let restsAtTop = activeCueID == nil || target == firstID
        let anchor: UnitPoint = restsAtTop ? .top : UnitPoint(x: 0.5, y: 0.4)
        scroll(to: target, anchor: anchor, animated: animated, proxy: proxy)
        follow.lastCenteredCueID = activeCueID
    }

    private func scroll(to id: Int, anchor: UnitPoint, animated: Bool, proxy: ScrollViewProxy) {
        follow.beginProgrammaticScroll()
        if animated {
            withAnimation(.easeInOut(duration: 0.35)) {
                proxy.scrollTo(id, anchor: anchor)
            }
        } else {
            proxy.scrollTo(id, anchor: anchor)
        }
        follow.endProgrammaticScroll()
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
        var nextIndex = 0
        for cue in cues where colors[cue.speaker] == nil {
            colors[cue.speaker] = speakerPalette[nextIndex % speakerPalette.count]
            nextIndex += 1
        }
        return colors
    }
}

/// Owns the transcript's follow state and tells a user scroll apart from a
/// programmatic one. A reference type (not `@State`) so the AppKit
/// notification callbacks see live values.
@MainActor
final class TranscriptFollowCoordinator: ObservableObject {
    /// When true, the list keeps the active cue in view as playback advances.
    /// A genuine user scroll flips it off; a seek or the "Jump to current"
    /// pill flips it back on.
    @Published private(set) var isFollowing = true

    /// The cue the list was last programmatically centered on — the baseline
    /// for the "only recenter once the active cue has drifted far enough"
    /// band rule, so short advances don't cause constant scrolling.
    var lastCenteredCueID: Int?

    /// Recenter once the active cue is this many cues away from where we last
    /// centered. Because cue ids equal their array index, the gap is just the
    /// id difference. Approximates the "keep it in the middle band" rule
    /// without per-row geometry.
    private let recenterThreshold = 3

    private var isProgrammaticScrolling = false
    private weak var scrollView: NSScrollView?
    private var observers: [NSObjectProtocol] = []

    func reattachToActiveCue() {
        isFollowing = true
    }

    func shouldRecenter(forActiveCueID id: Int) -> Bool {
        guard let last = lastCenteredCueID else {
            return true
        }
        return abs(id - last) >= recenterThreshold
    }

    func beginProgrammaticScroll() {
        isProgrammaticScrolling = true
    }

    /// Clears the guard a little after the (uncompletable-to-observe) scroll
    /// animation would have settled — `scrollTo` has no completion callback.
    func endProgrammaticScroll() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.isProgrammaticScrolling = false
        }
    }

    func attach(to scrollView: NSScrollView) {
        guard self.scrollView !== scrollView else {
            return
        }
        detach()
        self.scrollView = scrollView

        // The queue is `.main`, so the notification fires on the main thread;
        // `assumeIsolated` lets the `@Sendable` block call back into this
        // MainActor-isolated coordinator without an extra async hop.
        let handler: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.userDidScroll() }
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSScrollView.willStartLiveScrollNotification, object: scrollView, queue: .main, using: handler
        ))
        observers.append(center.addObserver(
            forName: NSScrollView.didLiveScrollNotification, object: scrollView, queue: .main, using: handler
        ))
    }

    /// Removes the live-scroll observers. Called from the view's `onDisappear`
    /// (and before re-attaching to a new scroll view).
    func detach() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        scrollView = nil
    }

    private func userDidScroll() {
        guard !isProgrammaticScrolling, isFollowing else {
            return
        }
        isFollowing = false
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
    let usesHours: Bool
    let canSeek: Bool
    let onSeek: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    /// Tighter rhythm within a speaker's turn, a clear beat between turns.
    private var topPadding: CGFloat {
        if isFirst { return 0 }
        return showsSpeaker ? 20 : 8
    }

    /// A touch more tint in dark mode — the same accent reads weaker against a
    /// dark field.
    private var activeTintOpacity: Double {
        colorScheme == .dark ? 0.12 : 0.08
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
                TranscriptTimestampButton(seconds: cue.startSeconds, color: speakerColor, usesHours: usesHours, canSeek: canSeek, onSeek: onSeek)
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
            isActive ? speakerColor.opacity(activeTintOpacity) : .clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .overlay(alignment: .leading) {
            if isActive {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(speakerColor)
                    .frame(width: 3)
                    .padding(.vertical, 4)
            }
        }
        .padding(.top, topPadding)
    }
}

/// The clickable `[MM:SS]` timestamp. Bare accent mono-digits at rest; a
/// filled pill + pointing-hand cursor on hover, so it only reads as a button
/// when the pointer is on it (there are hundreds of these).
private struct TranscriptTimestampButton: View {
    let seconds: Double
    /// Matches the cue's speaker color so the timestamp reads as part of that
    /// speaker's turn rather than a fixed accent.
    let color: Color
    let usesHours: Bool
    let canSeek: Bool
    let onSeek: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSeek) {
            Text(TimenoteFormat.bracketedTimestamp(seconds, forcingHours: usesHours))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(canSeek ? color : Color.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    (canSeek && isHovered) ? color.opacity(0.15) : .clear,
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
}

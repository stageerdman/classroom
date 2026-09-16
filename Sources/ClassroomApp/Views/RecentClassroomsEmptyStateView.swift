import ClassroomCore
import SwiftUI

/// The launch screen once at least one recent classroom exists. Recents are
/// the primary way back in — a plain list, not a thumbnail grid, since
/// `RecentClassroom` only ever has a path (no stored date/thumbnail) and in
/// practice there are a handful of these, not dozens. Opening a different
/// folder is still always available, just demoted to a secondary link.
struct RecentClassroomsEmptyStateView: View {
    let recents: [RecentClassroom]
    let errorMessage: String?
    let onOpen: (RecentClassroom) -> Void
    let onRemove: (RecentClassroom) -> Void
    let onOpenDifferent: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            if let wordmark = BrandImage.wordmark.image {
                wordmark
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 120)
            }

            Text("Recent Classrooms")
                .font(.headline)
                .foregroundStyle(.secondary)

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            VStack(spacing: 0) {
                ForEach(recents) { recent in
                    if recent.id != recents.first?.id {
                        Divider()
                    }
                    RecentClassroomRow(
                        recent: recent,
                        onOpen: { onOpen(recent) },
                        onRemove: { onRemove(recent) }
                    )
                }
            }
            .frame(maxWidth: 420)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))

            Button("Open a Different Folder...", action: onOpenDifferent)
                .buttonStyle(.link)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A row's "missing" state is checked live at render time (not cached in
/// `RecentClassroom`/the store) — cheap for the handful of rows this list
/// ever holds, and avoids the list showing stale truth about a folder that
/// was unplugged, reconnected, or renamed since last launch.
private struct RecentClassroomRow: View {
    let recent: RecentClassroom
    let onOpen: () -> Void
    let onRemove: () -> Void
    @State private var isHovering = false

    private var isMissing: Bool {
        !FileManager.default.fileExists(atPath: recent.path)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .foregroundStyle(isMissing ? .tertiary : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(recent.name)
                    .fontWeight(.medium)
                    .foregroundStyle(isMissing ? .tertiary : .primary)
                Text(recent.path)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if isMissing {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.tertiary)
                    .help("Folder not found")
            }

            if isHovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove from Recents")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Remove from Recents", action: onRemove)
        }
    }
}

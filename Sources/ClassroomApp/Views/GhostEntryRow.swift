import ClassroomCore
import SwiftUI

/// A single ghost entry (file or folder on disk that isn't part of the
/// recognized Lesson/Category structure) inside the module editor's
/// sidebar. Folders expand recursively, via their own live ghost listing,
/// so nothing on disk stays hidden while reorganizing — and files/folders
/// can be dragged into another folder to move them, same as a real lesson.
struct GhostEntryRow: View {
    @ObservedObject var viewModel: ClassroomBrowserViewModel
    let ghost: GhostEntry

    /// Drag payloads for ghost items are prefixed so drop targets (which
    /// also accept real lesson-ID drags for reparenting) can tell the two
    /// apart. See `GhostDragPayload`.
    static let dragPrefix = "ghost-path:"

    var body: some View {
        if ghost.isDirectory {
            DisclosureGroup {
                ForEach(children) { child in
                    GhostEntryRow(viewModel: viewModel, ghost: child)
                }
            } label: {
                row
            }
            .contextMenu {
                Button("Transform to Lesson") {
                    viewModel.beginTransform(folderURL: ghost.url)
                }
            }
            .dropDestination(for: String.self) { ids, _ in
                guard let payload = ids.first, let path = Self.strippedGhostPath(payload) else {
                    return false
                }
                viewModel.moveGhost(atAbsolutePath: path, intoFolderURL: ghost.url)
                return true
            }
            .draggable(Self.dragPrefix + ghost.url.path)
        } else {
            row
                .draggable(Self.dragPrefix + ghost.url.path)
        }
    }

    private var children: [GhostEntry] {
        viewModel.ghostEntries(inFolderURL: ghost.url)
    }

    private var row: some View {
        HStack {
            Image(systemName: ghost.isDirectory ? "folder" : "doc")
                .foregroundStyle(.tertiary)
                .frame(width: 18, alignment: .center)
            Text(ghost.name)
                .italic()
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer()
        }
        .opacity(0.6)
        .help("Not part of the lesson/category structure yet")
    }

    /// Strips the ghost-drag prefix off a dropped ID, or returns `nil` if
    /// the drop was actually a real lesson-ID drag (reparenting), not a
    /// ghost move.
    static func strippedGhostPath(_ payload: String) -> String? {
        guard payload.hasPrefix(dragPrefix) else {
            return nil
        }
        return String(payload.dropFirst(dragPrefix.count))
    }
}
